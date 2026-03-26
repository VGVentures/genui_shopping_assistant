/// In-memory shopping context that tracks cart state and user preferences
/// across the conversation.
///
/// This is passed through the Genkit generation pipeline so that tools and
/// the model can personalize responses — e.g., "you already have X in your
/// cart" or prioritizing products that match stated preferences.
class ShoppingContext {
  final List<CartItem> _cartItems = [];
  final Map<String, String> _preferences = {};

  /// Items currently in the user's cart.
  List<CartItem> get cartItems => List.unmodifiable(_cartItems);

  /// User preferences (e.g., preferred category, budget).
  Map<String, String> get preferences => Map.unmodifiable(_preferences);

  /// Adds a product to the cart. Returns `true` if it was newly added.
  bool addToCart(String productName, double price) {
    if (_cartItems.any((item) => item.productName == productName)) {
      return false;
    }
    _cartItems.add(CartItem(productName: productName, price: price));
    return true;
  }

  /// Sets a user preference key-value pair.
  void setPreference(String key, String value) {
    _preferences[key] = value;
  }

  /// Total price of all items in the cart.
  double get cartTotal =>
      _cartItems.fold(0, (sum, item) => sum + item.price);

  /// Returns a summary string suitable for injecting into the system prompt.
  String toPromptSummary() {
    final buf = StringBuffer();
    if (_cartItems.isNotEmpty) {
      buf.writeln('## Current Cart');
      for (final item in _cartItems) {
        buf.writeln('- ${item.productName} (\$${item.price.toStringAsFixed(2)})');
      }
      buf.writeln('Cart total: \$${cartTotal.toStringAsFixed(2)}');
      buf.writeln();
    }
    if (_preferences.isNotEmpty) {
      buf.writeln('## User Preferences');
      for (final entry in _preferences.entries) {
        buf.writeln('- ${entry.key}: ${entry.value}');
      }
      buf.writeln();
    }
    return buf.toString();
  }

  /// Returns `true` if the given product name is already in the cart.
  bool isInCart(String productName) =>
      _cartItems.any((item) => item.productName == productName);
}

/// A single item in the shopping cart.
class CartItem {
  const CartItem({required this.productName, required this.price});

  final String productName;
  final double price;
}
