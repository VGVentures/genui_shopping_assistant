import 'dart:convert';
import 'dart:io';

import 'package:genkit/genkit.dart';
import 'package:genkit_google_genai/genkit_google_genai.dart';
import 'package:genkit_shelf/genkit_shelf.dart';
import 'package:schemantic/schemantic.dart';
import 'package:shopping_assistant_backend/product_data.dart';
import 'package:shopping_assistant_backend/shopping_context.dart';

void main() async {
  final apiKey = Platform.environment['GOOGLE_API_KEY'] ?? '';
  if (apiKey.isEmpty) {
    stderr.writeln('ERROR: GOOGLE_API_KEY is not set.');
    exit(1);
  }

  final ai = Genkit(
    plugins: [
      googleAI(apiKey: apiKey),
      RetryPlugin(),
    ],
  );

  // Exposes searchProducts as a standalone flow the Flutter app can call.
  final searchProductsFlow = ai
      .defineFlow<Map<String, dynamic>, String, void, void>(
        name: 'searchProductsFlow',
        fn: (input, _) async {
          final query = input['query'] as String;
          final category = input['category'] as String?;
          final maxResults = (input['maxResults'] as num?)?.toInt() ?? 5;
          final cartItems =
              (input['cartItems'] as List<dynamic>?)
                  ?.map((e) => e as String)
                  .toList() ??
              [];

          final shoppingContext = ShoppingContext();
          for (final item in cartItems) {
            shoppingContext.addToCart(item, 0);
          }

          final results = searchProducts(
            query: query,
            category: category,
            maxResults: maxResults,
          );

          final json = results.map((p) {
            final map = p.toJson();
            if (shoppingContext.isInCart(p.name)) map['inCart'] = true;
            return map;
          }).toList();

          return jsonEncode(json);
        },
      );
  // quickRecommendationFlow — structured output, no UI dependency.
  final quickRecommendationFlow = ai
      .defineFlow<String, List<Map<String, dynamic>>, void, void>(
        name: 'quickRecommendationFlow',
        fn: (userQuery, _) async {
          final response = await ai
              .generate<GeminiOptions, List<Map<String, dynamic>>>(
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
                        text:
                            'You are a shopping assistant. Given the user\'s '
                            'request, recommend 3-5 products from these '
                            'categories: running shoes, accessories, apparel, '
                            'electronics. Return ONLY the JSON array — no '
                            'markdown, no extra text.',
                      ),
                    ],
                  ),
                  Message(
                    role: Role.user,
                    content: [TextPart(text: userQuery)],
                  ),
                ],
                outputSchema: SchemanticType.from<List<Map<String, dynamic>>>(
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
                ),
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
          return response.output!;
        },
      );

  await startFlowServer(
    flows: [searchProductsFlow, quickRecommendationFlow],
    port: 3400,
    cors: {
      'origin': Platform.environment['ALLOWED_ORIGIN'] ?? 'http://localhost:*',
    },
  );

  stdout.writeln('Server running on http://localhost:3400');
}
