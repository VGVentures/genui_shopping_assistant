/// Hardcoded product catalog for the shopping assistant demo.
///
/// In a real app this would come from a backend API or database.
/// For this demo, it gives the model something to "search" via the
/// Genkit searchProducts tool.
class Product {
  const Product({
    required this.name,
    required this.price,
    required this.description,
    required this.category,
    this.brand,
    this.rating,
  });

  final String name;
  final double price;
  final String description;
  final String category;
  final String? brand;
  final double? rating;

  Map<String, dynamic> toJson() => {
        'name': name,
        'price': price,
        'description': description,
        'category': category,
        if (brand != null) 'brand': brand,
        if (rating != null) 'rating': rating,
      };
}

/// The full product inventory available for search.
const productInventory = <Product>[
  // Running shoes
  Product(
    name: 'UltraBoost 22',
    price: 189.99,
    description: 'Responsive Boost midsole with Primeknit upper for all-day comfort.',
    category: 'running shoes',
    brand: 'Adidas',
    rating: 4.7,
  ),
  Product(
    name: 'Air Zoom Pegasus 40',
    price: 129.99,
    description: 'Versatile everyday running shoe with Zoom Air cushioning.',
    category: 'running shoes',
    brand: 'Nike',
    rating: 4.5,
  ),
  Product(
    name: 'Fresh Foam 1080v13',
    price: 159.99,
    description: 'Plush Fresh Foam X midsole for long-distance comfort.',
    category: 'running shoes',
    brand: 'New Balance',
    rating: 4.6,
  ),
  Product(
    name: 'Gel-Nimbus 26',
    price: 159.99,
    description: 'FF Blast Plus cushioning with PureGEL inserts for smooth transitions.',
    category: 'running shoes',
    brand: 'ASICS',
    rating: 4.4,
  ),
  Product(
    name: 'Clifton 9',
    price: 144.99,
    description: 'Lightweight and cushioned with compression-molded EVA midsole.',
    category: 'running shoes',
    brand: 'Hoka',
    rating: 4.8,
  ),

  // Accessories
  Product(
    name: 'Performance Running Socks (3-pack)',
    price: 18.99,
    description: 'Moisture-wicking blend with arch support and blister protection.',
    category: 'accessories',
    brand: 'Balega',
    rating: 4.6,
  ),
  Product(
    name: 'Comfort Sport Insoles',
    price: 34.99,
    description: 'Gel cushioning insoles for extra shock absorption during runs.',
    category: 'accessories',
    brand: 'Superfeet',
    rating: 4.3,
  ),
  Product(
    name: 'Reflective Running Vest',
    price: 29.99,
    description: '360-degree reflectivity for safe early-morning and night runs.',
    category: 'accessories',
    rating: 4.5,
  ),
  Product(
    name: 'Sports Sunglasses',
    price: 59.99,
    description: 'Polarized lenses with lightweight, non-slip frame for active use.',
    category: 'accessories',
    brand: 'Goodr',
    rating: 4.4,
  ),

  // Apparel
  Product(
    name: 'Dri-FIT Running Tee',
    price: 34.99,
    description: 'Lightweight moisture-wicking fabric keeps you dry on every run.',
    category: 'apparel',
    brand: 'Nike',
    rating: 4.5,
  ),
  Product(
    name: 'Run Visible Jacket',
    price: 89.99,
    description: 'Water-resistant jacket with reflective details for low-light runs.',
    category: 'apparel',
    brand: 'Brooks',
    rating: 4.6,
  ),
  Product(
    name: 'Mesh Running Shorts',
    price: 44.99,
    description: 'Built-in brief liner with zippered pocket for keys or cards.',
    category: 'apparel',
    brand: 'Lululemon',
    rating: 4.7,
  ),
  Product(
    name: 'Compression Running Tights',
    price: 64.99,
    description: 'Graduated compression for improved circulation and recovery.',
    category: 'apparel',
    brand: '2XU',
    rating: 4.3,
  ),

  // Electronics
  Product(
    name: 'Forerunner 265 GPS Watch',
    price: 449.99,
    description: 'AMOLED display with advanced training metrics and GPS tracking.',
    category: 'electronics',
    brand: 'Garmin',
    rating: 4.8,
  ),
  Product(
    name: 'Powerbeats Pro 2',
    price: 249.99,
    description: 'Secure-fit ear hooks with active noise cancellation for workouts.',
    category: 'electronics',
    brand: 'Beats',
    rating: 4.5,
  ),
  Product(
    name: 'Running Hydration Belt',
    price: 32.99,
    description: 'Two 10oz bottles with stretch mesh pocket for phone and fuel.',
    category: 'accessories',
    rating: 4.2,
  ),
];

/// Searches the product inventory by query and optional filters.
List<Product> searchProducts({
  required String query,
  String? category,
  int maxResults = 5,
}) {
  final lowerQuery = query.toLowerCase();
  var results = productInventory.where((p) {
    final matchesQuery = p.name.toLowerCase().contains(lowerQuery) ||
        p.description.toLowerCase().contains(lowerQuery) ||
        p.category.toLowerCase().contains(lowerQuery) ||
        (p.brand?.toLowerCase().contains(lowerQuery) ?? false);
    final matchesCategory =
        category == null || p.category.toLowerCase() == category.toLowerCase();
    return matchesQuery && matchesCategory;
  }).toList();

  // Sort by rating (highest first) for relevance.
  results.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));

  if (results.length > maxResults) {
    results = results.sublist(0, maxResults);
  }
  return results;
}
