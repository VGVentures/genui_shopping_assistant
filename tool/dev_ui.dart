/// Standalone Dart script that registers the same Genkit flows and tools
/// as the Flutter app, so the Genkit Dev UI can inspect and test them.
///
/// Run with: genkit start -- dart run tool/dev_ui.dart
import 'dart:convert';
import 'dart:io';

import 'package:genkit/genkit.dart';
import 'package:genkit_google_genai/genkit_google_genai.dart';
import 'package:genui_shopping_assistant/shopping_assistant/data/product_data.dart';
import 'package:schemantic/schemantic.dart';

void main() {
  final apiKey = Platform.environment['GOOGLE_API_KEY'] ?? '';
  if (apiKey.isEmpty) {
    print('ERROR: Set GOOGLE_API_KEY environment variable');
    exit(1);
  }

  final ai = Genkit(plugins: [googleAI(apiKey: apiKey), RetryPlugin()]);

  // --- searchProducts tool ---
  final searchProductsTool = ai.defineTool<Map<String, dynamic>, String>(
    name: 'searchProducts',
    description:
        'Searches the product inventory by keyword query. Returns '
        'matching products with name, price, description, category, '
        'brand, and rating.',
    inputSchema: SchemanticType.from<Map<String, dynamic>>(
      jsonSchema: {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'Search query.',
          },
          'category': {
            'type': 'string',
            'description': 'Optional category filter.',
          },
          'maxResults': {
            'type': 'integer',
            'description': 'Max results. Defaults to 5.',
          },
        },
        'required': ['query'],
      },
      parse: (json) => json as Map<String, dynamic>,
    ),
    fn: (input, _) async {
      final results = searchProducts(
        query: input['query'] as String,
        category: input['category'] as String?,
        maxResults: (input['maxResults'] as num?)?.toInt() ?? 5,
      );
      return jsonEncode(results.map((p) => p.toJson()).toList());
    },
  );

  // --- shoppingAssistantFlow ---
  ai.defineFlow<String, String, void, void>(
    name: 'shoppingAssistantFlow',
    inputSchema: SchemanticType.from<String>(
      jsonSchema: {'type': 'string'},
      parse: (json) => json as String,
    ),
    outputSchema: SchemanticType.from<String>(
      jsonSchema: {'type': 'string'},
      parse: (json) => json as String,
    ),
    fn: (userMessage, context) async {
      final response = await ai.generate<GeminiOptions, void>(
        model: googleAI.gemini('gemini-2.5-flash'),
        config: GeminiOptions(
          thinkingConfig: ThinkingConfig(
            thinkingBudget: 0,
            includeThoughts: false,
          ),
        ),
        messages: [
          Message(
            role: Role.system,
            content: [
              TextPart(
                text: 'You are a shopping assistant. Help users find products. '
                    'Use the searchProducts tool to find products, then describe '
                    'the results to the user.',
              ),
            ],
          ),
          Message(
            role: Role.user,
            content: [TextPart(text: userMessage)],
          ),
        ],
        tools: [searchProductsTool],
        maxTurns: 10,
        use: [
          retry(
            maxRetries: 3,
            initialDelayMs: 500,
            maxDelayMs: 5000,
            backoffFactor: 2,
            statuses: [
              StatusCodes.UNAVAILABLE,
              StatusCodes.RESOURCE_EXHAUSTED,
              StatusCodes.DEADLINE_EXCEEDED,
            ],
          ),
        ],
      );
      return response.text;
    },
  );

  // --- quickRecommendationFlow ---
  final recommendationSchema =
      SchemanticType.from<List<Map<String, dynamic>>>(
    jsonSchema: {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'productName': {'type': 'string'},
          'reason': {'type': 'string'},
          'category': {'type': 'string'},
          'priceRange': {'type': 'string'},
        },
        'required': ['productName', 'reason', 'category'],
      },
    },
    parse: (json) =>
        (json as List<dynamic>).cast<Map<String, dynamic>>(),
  );

  ai.defineFlow<String, List<Map<String, dynamic>>, void, void>(
    name: 'quickRecommendationFlow',
    inputSchema: SchemanticType.from<String>(
      jsonSchema: {'type': 'string'},
      parse: (json) => json as String,
    ),
    outputSchema: recommendationSchema,
    fn: (userQuery, context) async {
      final response = await ai.generate<GeminiOptions,
          List<Map<String, dynamic>>>(
        model: googleAI.gemini('gemini-2.5-flash'),
        config: GeminiOptions(
          thinkingConfig: ThinkingConfig(
            thinkingBudget: 0,
            includeThoughts: false,
          ),
        ),
        messages: [
          Message(
            role: Role.system,
            content: [
              TextPart(
                text: 'You are a shopping assistant. Given the user\'s '
                    'request, recommend 3-5 products from these categories: '
                    'running shoes, accessories, apparel, electronics. '
                    'Return ONLY the JSON array.',
              ),
            ],
          ),
          Message(
            role: Role.user,
            content: [TextPart(text: userQuery)],
          ),
        ],
        outputSchema: recommendationSchema,
        use: [
          retry(
            maxRetries: 3,
            initialDelayMs: 500,
            maxDelayMs: 5000,
            backoffFactor: 2,
          ),
        ],
      );
      return response.output!;
    },
  );

  print('Genkit Dev UI ready. Flows: shoppingAssistantFlow, quickRecommendationFlow');
  print('Tools: searchProducts');
}
