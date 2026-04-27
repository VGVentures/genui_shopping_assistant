import 'dart:convert';
import 'dart:io';

import 'package:genkit/genkit.dart';
import 'package:genkit_google_genai/genkit_google_genai.dart';
import 'package:genkit_shelf/genkit_shelf.dart';
import 'package:shopping_assistant_backend/product_data.dart';
import 'package:shopping_assistant_backend/shopping_context.dart';

void main() async {
  final apiKey = Platform.environment['GOOGLE_API_KEY'] ?? '';
  if (apiKey.isEmpty) {
    print('ERROR: GOOGLE_API_KEY is not set.');
    exit(1);
  }

  final ai = Genkit(
    plugins: [googleAI(apiKey: apiKey), RetryPlugin()],
  );

  final shoppingContext = ShoppingContext();

  // Exposes searchProducts as a standalone flow the Flutter app can call.
  final searchProductsFlow = ai.defineFlow<Map<String, dynamic>, String, void, void>(
    name: 'searchProductsFlow',
    fn: (input, _) async {
      final query = input['query'] as String;
      final category = input['category'] as String?;
      final maxResults = (input['maxResults'] as num?)?.toInt() ?? 5;
      final cartItems = (input['cartItems'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [];

      // Update cart context from Flutter app state.
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

await startFlowServer(
  flows: [searchProductsFlow],
  port: 3400,
  cors: {'origin': '*'},
);

  print('Server running on http://localhost:3400');
}