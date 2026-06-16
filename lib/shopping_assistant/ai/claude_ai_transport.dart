import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:genui_dartantic/genui_dartantic.dart';
import 'package:genui_shopping_assistant/shopping_assistant/catalog/shopping_catalog.dart';
import 'package:genui_shopping_assistant/shopping_assistant/prompt/shopping_prompt.dart';

const _anthropicApiKey = String.fromEnvironment('ANTHROPIC_API_KEY');

/// Creates and configures a [DartanticContentGenerator] backed by Anthropic
/// Claude Sonnet 4.6.
///
/// Pass the key at run time:
///   flutter run --dart-define=ANTHROPIC_API_KEY=sk-ant-...
DartanticContentGenerator buildClaudeContentGenerator() {
  return DartanticContentGenerator(
    provider: AnthropicProvider(apiKey: _anthropicApiKey),
    modelName: 'claude-sonnet-4-6',
    catalog: shoppingCatalog,
    systemInstruction: shoppingSystemInstructions,
  );
}
