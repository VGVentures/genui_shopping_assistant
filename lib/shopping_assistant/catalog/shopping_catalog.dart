import 'package:genui/genui.dart';
import 'package:genui_shopping_assistant/shopping_assistant/catalog/price_range_filter_item.dart';
import 'package:genui_shopping_assistant/shopping_assistant/catalog/product_card_item.dart';
import 'package:genui_shopping_assistant/shopping_assistant/catalog/product_carousel_item.dart';

/// The [Catalog] used by the shopping assistant.
///
/// Includes the standard GenUI basic items (column, text, button, card,
/// divider) for general layout, plus three custom items specific to this
/// shopping experience.
///
/// Note: every item in the catalog is included in the system prompt sent to
/// the AI, so catalog size directly affects token usage. Keep it focused.
final shoppingCatalog = Catalog(
  [
    CoreCatalogItems.column,
    CoreCatalogItems.text,
    CoreCatalogItems.button,
    CoreCatalogItems.card,
    CoreCatalogItems.divider,
    productCardItem,
    productCarouselItem,
    priceRangeFilterItem,
  ],
  // genui_dartantic 0.7.1 does not pass catalogId to BeginRenderingTool, so
  // the surface lookup falls back to genui's standardCatalogId constant.
  // Using that same value here ensures both the Claude and Gemini paths resolve
  // to this catalog correctly.
  catalogId: 'a2ui.org:standard_catalog_0_8_0',
);
