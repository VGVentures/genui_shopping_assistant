import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:genkit/genkit.dart' as genkit;
import 'package:genkit_google_genai/genkit_google_genai.dart';
import 'package:genui/genui.dart';
import 'package:genui_shopping_assistant/shopping_assistant/catalog/shopping_catalog.dart';
import 'package:genui_shopping_assistant/shopping_assistant/prompt/shopping_prompt.dart';
import 'package:json_schema_builder/json_schema_builder.dart' as jsb;
import 'package:logging/logging.dart';
import 'package:schemantic/schemantic.dart';

final _log = Logger('GenkitContentGenerator');

/// A [ContentGenerator] powered by Genkit with Google AI (Gemini).
///
/// This replaces `FirebaseAiContentGenerator` from the `genui_firebase_ai`
/// package, using Genkit's model-agnostic framework instead.
class GenkitContentGenerator implements ContentGenerator {
  /// Creates a [GenkitContentGenerator].
  ///
  /// Initializes Genkit with the Google AI plugin and sets up the GenUI
  /// tools (surfaceUpdate, beginRendering, deleteSurface) so the model
  /// can build interactive UI surfaces.
  GenkitContentGenerator({
    required Catalog catalog,
    required String systemInstruction,
  })  : _catalog = catalog,
        _systemInstruction = systemInstruction {
    const apiKey = String.fromEnvironment('GOOGLE_API_KEY');
    _genkit = genkit.Genkit(plugins: [googleAI(apiKey: apiKey)]);

    // Register GenUI tools with Genkit. These are the same tools that
    // genui_firebase_ai wires up behind the scenes — we just do it
    // explicitly now. Each tool needs an inputSchema so the model knows
    // what parameters to pass.
    SchemanticType<Map<String, dynamic>> _mapSchema(jsb.Schema schema) {
      // Schema is an extension type over Map<String, Object?>.
      // Round-trip through JSON to extract the underlying map.
      final jsonSchema =
          jsonDecode(jsonEncode(schema)) as Map<String, Object?>;
      return SchemanticType.from<Map<String, dynamic>>(
        jsonSchema: jsonSchema,
        parse: (json) => json as Map<String, dynamic>,
      );
    }

    _surfaceUpdateTool =
        _genkit.defineTool<Map<String, dynamic>, String>(
          name: 'surfaceUpdate',
          description: 'Updates a surface with a new set of components.',
          inputSchema: _mapSchema(
            A2uiSchemas.surfaceUpdateSchema(catalog),
          ),
          fn: (input, _) async {
            _handleSurfaceUpdate(input);
            final surfaceId = input[surfaceIdKey] as String;
            return 'UI Surface $surfaceId updated.';
          },
        );

    _beginRenderingTool =
        _genkit.defineTool<Map<String, dynamic>, String>(
          name: 'beginRendering',
          description:
              'Signals the client to begin rendering a surface with a root '
              'component.',
          inputSchema: _mapSchema(
            A2uiSchemas.beginRenderingSchemaNoCatalogId(),
          ),
          fn: (input, _) async {
            _handleBeginRendering(input);
            final surfaceId = input[surfaceIdKey] as String;
            return 'Surface $surfaceId rendered and waiting for user input.';
          },
        );

    _deleteSurfaceTool =
        _genkit.defineTool<Map<String, dynamic>, String>(
          name: 'deleteSurface',
          description: 'Removes a UI surface that is no longer needed.',
          inputSchema: _mapSchema(
            A2uiSchemas.surfaceDeletionSchema(),
          ),
          fn: (input, _) async {
            final surfaceId = input[surfaceIdKey] as String;
            _a2uiController.add(SurfaceDeletion(surfaceId: surfaceId));
            return 'Surface $surfaceId deleted.';
          },
        );
  }

  final Catalog _catalog;
  final String _systemInstruction;
  late final genkit.Genkit _genkit;
  late final genkit.Tool<Map<String, dynamic>, String> _surfaceUpdateTool;
  late final genkit.Tool<Map<String, dynamic>, String> _beginRenderingTool;
  late final genkit.Tool<Map<String, dynamic>, String> _deleteSurfaceTool;

  final _a2uiController = StreamController<A2uiMessage>.broadcast();
  final _textController = StreamController<String>.broadcast();
  final _errorController = StreamController<ContentGeneratorError>.broadcast();
  final _isProcessing = ValueNotifier<bool>(false);

  @override
  Stream<A2uiMessage> get a2uiMessageStream => _a2uiController.stream;

  @override
  Stream<String> get textResponseStream => _textController.stream;

  @override
  Stream<ContentGeneratorError> get errorStream => _errorController.stream;

  @override
  ValueListenable<bool> get isProcessing => _isProcessing;

  @override
  Future<void> sendRequest(
    ChatMessage message, {
    Iterable<ChatMessage>? history,
    A2UiClientCapabilities? clientCapabilities,
  }) async {
    _isProcessing.value = true;
    try {
      // Build Genkit messages from GenUI conversation history.
      final messages = _buildMessages(message, history);

      // Call Genkit generate with our tools. Genkit handles the tool-calling
      // loop automatically — when the model emits a tool call, Genkit invokes
      // our registered tool functions and feeds the results back.
      final response = await _genkit.generate<GeminiOptions, void>(
        model: googleAI.gemini('gemini-2.5-flash'),
        config: GeminiOptions(
          thinkingConfig: ThinkingConfig(
            thinkingBudget: 0,
            includeThoughts: false,
          ),
        ),
        messages: messages,
        tools: [_surfaceUpdateTool, _beginRenderingTool, _deleteSurfaceTool],
        maxTurns: 30,
      );

      // Emit any remaining text that isn't part of a tool call.
      final text = response.text;
      if (text.isNotEmpty) {
        _textController.add(text);
      }
    } catch (e, st) {
      _log.severe('Generation error: $e', e, st);
      debugPrint('GENKIT ERROR: $e');
      debugPrint('GENKIT STACK: $st');
      _errorController.add(ContentGeneratorError(e, st));
    } finally {
      _isProcessing.value = false;
    }
  }

  @override
  void dispose() {
    _a2uiController.close();
    _textController.close();
    _errorController.close();
    _isProcessing.dispose();
  }

  /// Converts GenUI [ChatMessage] history into Genkit [genkit.Message] list.
  List<genkit.Message> _buildMessages(
    ChatMessage current,
    Iterable<ChatMessage>? history,
  ) {
    final messages = <genkit.Message>[];

    // System message with catalog schema and instructions.
    final catalogSchema = _catalog.definition;
    final systemPrompt = '$_systemInstruction\n\n'
        '${genUiTechPrompt(['surfaceUpdate', 'beginRendering', 'deleteSurface'])}\n\n'
        '## Available UI Components\n\n'
        '${jsonEncode(catalogSchema.value)}';
    messages.add(genkit.Message(
      role: genkit.Role.system,
      content: [genkit.TextPart(text: systemPrompt)],
    ));

    // Convert history.
    if (history != null) {
      for (final msg in history) {
        final converted = _convertChatMessage(msg);
        if (converted != null) messages.add(converted);
      }
    }

    // Convert current message.
    final converted = _convertChatMessage(current);
    if (converted != null) messages.add(converted);

    return messages;
  }

  /// Converts a single GenUI [ChatMessage] to a Genkit [genkit.Message].
  genkit.Message? _convertChatMessage(ChatMessage msg) {
    return switch (msg) {
      UserMessage(:final text) => genkit.Message(
          role: genkit.Role.user,
          content: [genkit.TextPart(text: text)],
        ),
      UserUiInteractionMessage(:final text) => genkit.Message(
          role: genkit.Role.user,
          content: [genkit.TextPart(text: text)],
        ),
      AiTextMessage(:final text) => genkit.Message(
          role: genkit.Role.model,
          content: [genkit.TextPart(text: text)],
        ),
      AiUiMessage(:final parts) => genkit.Message(
          role: genkit.Role.model,
          content: [
            genkit.TextPart(
              text: parts
                  .whereType<TextPart>()
                  .map((p) => p.text)
                  .join(),
            ),
          ],
        ),
      InternalMessage(:final text) => genkit.Message(
          role: genkit.Role.system,
          content: [genkit.TextPart(text: text)],
        ),
      ToolResponseMessage() => null,
    };
  }

  /// Handles a surfaceUpdate tool call by parsing components and emitting
  /// A2UI messages.
  void _handleSurfaceUpdate(Map<String, dynamic> args) {
    final surfaceId = args[surfaceIdKey] as String;
    final rawComponents = args['components'] as List<dynamic>? ?? [];
    final components = rawComponents.map((e) {
      final component = e as Map<String, dynamic>;
      return Component(
        id: component['id'] as String,
        componentProperties: Map<String, Object?>.from(
          component['component'] as Map,
        ),
        weight: (component['weight'] as num?)?.toInt(),
      );
    }).toList();
    _a2uiController
        .add(SurfaceUpdate(surfaceId: surfaceId, components: components));
  }

  /// Handles a beginRendering tool call.
  void _handleBeginRendering(Map<String, dynamic> args) {
    final surfaceId = args[surfaceIdKey] as String;
    final root = args['root'] as String? ?? 'root';
    _a2uiController.add(BeginRendering(
      surfaceId: surfaceId,
      root: root,
      catalogId: _catalog.catalogId,
    ));
  }
}

/// Builds and returns a [GenkitContentGenerator] configured for the shopping
/// assistant.
GenkitContentGenerator buildGenkitContentGenerator() {
  return GenkitContentGenerator(
    catalog: shoppingCatalog,
    systemInstruction:
        shoppingSystemInstructions + GenUiPromptFragments.basicChat,
  );
}
