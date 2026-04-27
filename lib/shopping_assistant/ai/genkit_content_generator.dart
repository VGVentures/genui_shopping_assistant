import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:genkit/genkit.dart' as genkit;
import 'package:genkit_google_genai/genkit_google_genai.dart';
import 'package:genui/genui.dart';
import 'package:genui_shopping_assistant/shopping_assistant/catalog/shopping_catalog.dart';
import 'package:genui_shopping_assistant/shopping_assistant/data/shopping_context.dart';
import 'package:genui_shopping_assistant/shopping_assistant/prompt/shopping_prompt.dart';
import 'package:http/http.dart' as http;
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
    _genkit = genkit.Genkit(
      plugins: [googleAI(apiKey: apiKey), genkit.RetryPlugin()],
    );

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

    // Define a searchProducts tool so the model can look up products from
    // the inventory by query, category, and result limit.
    _searchProductsTool =
        _genkit.defineTool<Map<String, dynamic>, String>(
          name: 'searchProducts',
          description:
              'Searches the product inventory by keyword query. Returns '
              'matching products with name, price, description, category, '
              'brand, and rating. Use this to find products before rendering '
              'them with surfaceUpdate/beginRendering.',
          inputSchema: SchemanticType.from<Map<String, dynamic>>(
            jsonSchema: {
              'type': 'object',
              'properties': {
                'query': {
                  'type': 'string',
                  'description':
                      'Search query — matches product name, description, '
                      'category, or brand.',
                },
                'category': {
                  'type': 'string',
                  'description':
                      'Optional category filter (e.g., "running shoes", '
                      '"accessories", "apparel", "electronics").',
                },
                'maxResults': {
                  'type': 'integer',
                  'description':
                      'Maximum number of results to return. Defaults to 5.',
                },
              },
              'required': ['query'],
            },
            parse: (json) => json as Map<String, dynamic>,
          ),
          fn: (input, _) async {
            // Call the backend server instead of searching locally.
            final uri = Uri.parse('http://localhost:3400/searchProductsFlow');
            final cartItems = _shoppingContext.cartItems.map((i) => i.productName).toList();
            
            final response = await http.post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'data': {
                  'query': input['query'],
                  if (input['category'] != null) 'category': input['category'],
                  if (input['maxResults'] != null) 'maxResults': input['maxResults'],
                  'cartItems': cartItems,
                }
              }),
            );
            
            final decoded = jsonDecode(response.body) as Map<String, dynamic>;
            return decoded['result'] as String;
          },
        );

    // Define a quick-recommendation flow that uses structured output.
    // Instead of parsing free-form text, outputSchema guarantees the model
    // returns JSON conforming to our ProductRecommendation schema.
    _quickRecommendationFlow =
        _genkit.defineFlow<String, List<Map<String, dynamic>>, void, void>(
          name: 'quickRecommendationFlow',
          outputSchema: SchemanticType.from<List<Map<String, dynamic>>>(
            jsonSchema: {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'productName': {
                    'type': 'string',
                    'description': 'Name of the recommended product.',
                  },
                  'reason': {
                    'type': 'string',
                    'description':
                        'One-sentence reason why this product is recommended.',
                  },
                  'category': {
                    'type': 'string',
                    'description': 'Product category.',
                  },
                  'priceRange': {
                    'type': 'string',
                    'description':
                        'Approximate price range, e.g. "\$50-\$100".',
                  },
                },
                'required': ['productName', 'reason', 'category'],
              },
            },
            parse: (json) => (json as List<dynamic>)
                .cast<Map<String, dynamic>>(),
          ),
          fn: (userQuery, context) async {
            final response = await _genkit.generate<GeminiOptions,
                List<Map<String, dynamic>>>(
              model: googleAI.gemini('gemini-2.5-flash'),
              config: GeminiOptions(
                thinkingConfig: ThinkingConfig(
                  thinkingBudget: 0,
                  includeThoughts: false,
                ),
              ),
              messages: [
                genkit.Message(
                  role: genkit.Role.system,
                  content: [
                    genkit.TextPart(
                      text:
                          'You are a shopping assistant. Given the user\'s '
                          'request, recommend 3-5 products from these '
                          'categories: running shoes, accessories, apparel, '
                          'electronics. Return ONLY the JSON array — no '
                          'markdown, no extra text.',
                    ),
                  ],
                ),
                genkit.Message(
                  role: genkit.Role.user,
                  content: [genkit.TextPart(text: userQuery)],
                ),
              ],
              outputSchema: SchemanticType.from<List<Map<String, dynamic>>>(
                jsonSchema: {
                  'type': 'array',
                  'items': {
                    'type': 'object',
                    'properties': {
                      'productName': {
                        'type': 'string',
                        'description': 'Name of the recommended product.',
                      },
                      'reason': {
                        'type': 'string',
                        'description':
                            'One-sentence reason why this is recommended.',
                      },
                      'category': {
                        'type': 'string',
                        'description': 'Product category.',
                      },
                      'priceRange': {
                        'type': 'string',
                        'description':
                            'Approximate price range, e.g. "\$50-\$100".',
                      },
                    },
                    'required': ['productName', 'reason', 'category'],
                  },
                },
                parse: (json) => (json as List<dynamic>)
                    .cast<Map<String, dynamic>>(),
              ),
              use: [
                genkit.retry(
                  maxRetries: 3,
                  initialDelayMs: 500,
                  maxDelayMs: 5000,
                  backoffFactor: 2,
                  statuses: [
                    genkit.StatusCodes.UNAVAILABLE,
                    genkit.StatusCodes.RESOURCE_EXHAUSTED,
                    genkit.StatusCodes.DEADLINE_EXCEEDED,
                  ],
                ),
              ],
            );
            return response.output!;
          },
        );

    // Define the shopping assistant flow. Flows are Genkit's core abstraction
    // for named, observable, composable units of AI work.
    _shoppingAssistantFlow =
        _genkit.defineFlow<List<genkit.Message>, String, void, void>(
          name: 'shoppingAssistantFlow',
          fn: (messages, context) async {
            final response = await _genkit.generate<GeminiOptions, void>(
              model: googleAI.gemini('gemini-2.5-flash'),
              config: GeminiOptions(
                thinkingConfig: ThinkingConfig(
                  thinkingBudget: 0,
                  includeThoughts: false,
                ),
              ),
              messages: messages,
              tools: [
                _surfaceUpdateTool,
                _beginRenderingTool,
                _deleteSurfaceTool,
                _searchProductsTool,
              ],
              maxTurns: 30,
              use: [
                genkit.retry(
                  maxRetries: 3,
                  initialDelayMs: 500,
                  maxDelayMs: 5000,
                  backoffFactor: 2,
                  statuses: [
                    genkit.StatusCodes.UNAVAILABLE,
                    genkit.StatusCodes.RESOURCE_EXHAUSTED,
                    genkit.StatusCodes.DEADLINE_EXCEEDED,
                  ],
                ),
              ],
            );
            return response.text;
          },
        );
  }

  final Catalog _catalog;
  final String _systemInstruction;
  final ShoppingContext _shoppingContext = ShoppingContext();
  late final genkit.Genkit _genkit;
  late final genkit.Tool<Map<String, dynamic>, String> _surfaceUpdateTool;
  late final genkit.Tool<Map<String, dynamic>, String> _beginRenderingTool;
  late final genkit.Tool<Map<String, dynamic>, String> _deleteSurfaceTool;
  late final genkit.Tool<Map<String, dynamic>, String> _searchProductsTool;
  late final genkit.Flow<String, List<Map<String, dynamic>>, void, void>
      _quickRecommendationFlow;
  late final genkit.Flow<List<genkit.Message>, String, void, void>
      _shoppingAssistantFlow;

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
      // Update the shopping context with cart events and user preferences
      // so subsequent generations can personalize responses.
      _trackCartEvent(message);
      _trackPreferences(message);

      // Build Genkit messages from GenUI conversation history.
      final messages = _buildMessages(message, history);

      // Check if this looks like a recommendation request. If so, use the
      // structured output flow to get typed recommendations first, then
      // feed them into the main flow so it can render product cards.
      final userText = (message is UserMessage) ? message.text : '';
      if (_isRecommendationQuery(userText)) {
        await _handleRecommendationQuery(userText, messages);
        return;
      }

      // Run the shopping assistant flow. The flow encapsulates the generate
      // call with tools, making it a named, observable unit of AI work.
      final text = await _shoppingAssistantFlow(messages);

      // Emit any remaining text that isn't part of a tool call.
      if (text.isNotEmpty) {
        _textController.add(text);
      }
    } catch (e, st) {
      _log.severe('Generation error: $e', e, st);
      debugPrint('GENKIT ERROR: $e');
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

  /// Returns `true` if the user's message looks like a recommendation request.
  bool _isRecommendationQuery(String text) {
    final lower = text.toLowerCase();
    const triggers = [
      'what should i buy',
      'recommend',
      'suggestion',
      'what do you suggest',
      'help me choose',
      'best picks',
      'top picks',
      'what\'s good',
      'whats good',
    ];
    return triggers.any(lower.contains);
  }

  /// Uses the structured output flow to get typed recommendations, then
  /// feeds them into the main shopping assistant flow for UI rendering.
  Future<void> _handleRecommendationQuery(
    String userText,
    List<genkit.Message> messages,
  ) async {
    // Get structured recommendations via outputSchema — guaranteed JSON.
    final recommendations = await _quickRecommendationFlow(userText);
    _log.info(
      'Structured recommendations: ${jsonEncode(recommendations)}',
    );

    // Inject the structured recommendations into the conversation so the
    // main flow can render them as product cards.
    messages.add(genkit.Message(
      role: genkit.Role.user,
      content: [
        genkit.TextPart(
          text: 'Here are structured product recommendations I got. '
              'Please search for these products and display them as a '
              'ProductCarousel. For each recommendation, include the '
              'reason it was recommended.\n\n'
              '${jsonEncode(recommendations)}',
        ),
      ],
    ));

    final text = await _shoppingAssistantFlow(messages);
    if (text.isNotEmpty) {
      _textController.add(text);
    }
  }

  /// Extracts budget or category preferences from user text messages.
  void _trackPreferences(ChatMessage message) {
    if (message is! UserMessage) return;
    final text = message.text.toLowerCase();
    // Detect budget mentions like "under $100" or "budget is $50".
    final budgetMatch =
        RegExp(r'(?:under|budget[^$]*|less than)\s*\$(\d+)').firstMatch(text);
    if (budgetMatch != null) {
      _shoppingContext.setPreference('budget', '\$${budgetMatch.group(1)}');
    }
    // Detect category preferences.
    const categories = ['running shoes', 'accessories', 'apparel', 'electronics'];
    for (final cat in categories) {
      if (text.contains(cat)) {
        _shoppingContext.setPreference('preferredCategory', cat);
        break;
      }
    }
  }

  /// Extracts addToCart events from user interaction messages and updates
  /// the [_shoppingContext] so the model and tools can see what's in the cart.
  void _trackCartEvent(ChatMessage message) {
    if (message is! UserUiInteractionMessage) return;
    final text = message.text;
    // The interaction message text contains the event description.
    // Look for addToCart mentions and try to extract the product details.
    if (!text.toLowerCase().contains('addtocart')) return;
    try {
      // GenUI formats the event context as JSON within the message.
      final match = RegExp(r'\{[^}]*productName[^}]*\}').firstMatch(text);
      if (match != null) {
        final data = jsonDecode(match.group(0)!) as Map<String, dynamic>;
        final name = data['productName'] as String?;
        final price = (data['price'] as num?)?.toDouble();
        if (name != null && price != null) {
          _shoppingContext.addToCart(name, price);
          _log.info('Cart updated: added $name (\$$price)');
        }
      }
    } catch (e) {
      _log.fine('Could not parse cart event: $e');
    }
  }

  /// Converts GenUI [ChatMessage] history into Genkit [genkit.Message] list.
  List<genkit.Message> _buildMessages(
    ChatMessage current,
    Iterable<ChatMessage>? history,
  ) {
    final messages = <genkit.Message>[];

    // System message with catalog schema, instructions, and current context.
    final catalogSchema = _catalog.definition;
    final contextSummary = _shoppingContext.toPromptSummary();
    final systemPrompt = '$_systemInstruction\n\n'
        '${genUiTechPrompt(['surfaceUpdate', 'beginRendering', 'deleteSurface'])}\n\n'
        '## Available UI Components\n\n'
        '${jsonEncode(catalogSchema.value)}'
        '${contextSummary.isNotEmpty ? '\n\n$contextSummary' : ''}';
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
