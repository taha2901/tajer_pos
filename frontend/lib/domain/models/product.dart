import 'enums.dart';

class Category {
  const Category({required this.id, required this.name});
  final String id;
  final String name;
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.barcode,
    required this.sku,
    required this.categoryId,
    required this.unit,
    required this.purchasePrice,
    required this.sellingPrice,
    required this.wholesalePrice,
    required this.halfWholesalePrice,
    required this.stock,
    required this.minStock,
    required this.createdAt,
    this.supplierId,
    this.description = '',
    this.imagePath,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String barcode;
  final String sku;
  final String categoryId;
  final String unit;
  final double purchasePrice;
  final double sellingPrice;
  final double wholesalePrice;
  final double halfWholesalePrice;
  final double stock;
  final double minStock;
  final String? supplierId;
  final String description;
  final String? imagePath;
  final bool isActive;
  final DateTime createdAt;

  bool get isOutOfStock => stock <= 0;
  bool get isLowStock => stock > 0 && stock <= minStock;
  double get stockValue => stock > 0 ? stock * purchasePrice : 0;
  double get margin => sellingPrice - purchasePrice;
  double get marginPercent => purchasePrice == 0 ? 0 : margin / purchasePrice * 100;

  double priceFor(PriceTier tier) => switch (tier) {
        PriceTier.wholesale => wholesalePrice,
        PriceTier.halfWholesale => halfWholesalePrice,
        _ => sellingPrice,
      };

  Product copyWith({
    String? name,
    String? barcode,
    String? sku,
    String? categoryId,
    String? unit,
    double? purchasePrice,
    double? sellingPrice,
    double? wholesalePrice,
    double? halfWholesalePrice,
    double? stock,
    double? minStock,
    String? Function()? supplierId,
    String? description,
    String? Function()? imagePath,
    bool? isActive,
  }) {
    return Product(
      id: id,
      createdAt: createdAt,
      name: name ?? this.name,
      barcode: barcode ?? this.barcode,
      sku: sku ?? this.sku,
      categoryId: categoryId ?? this.categoryId,
      unit: unit ?? this.unit,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      wholesalePrice: wholesalePrice ?? this.wholesalePrice,
      halfWholesalePrice: halfWholesalePrice ?? this.halfWholesalePrice,
      stock: stock ?? this.stock,
      minStock: minStock ?? this.minStock,
      supplierId: supplierId != null ? supplierId() : this.supplierId,
      description: description ?? this.description,
      imagePath: imagePath != null ? imagePath() : this.imagePath,
      isActive: isActive ?? this.isActive,
    );
  }
}

/// Payload for creating / updating a product (no id, stock handled separately).
class ProductInput {
  const ProductInput({
    required this.name,
    required this.barcode,
    required this.sku,
    required this.categoryId,
    required this.unit,
    required this.purchasePrice,
    required this.sellingPrice,
    required this.wholesalePrice,
    required this.halfWholesalePrice,
    required this.minStock,
    this.openingStock = 0,
    this.supplierId,
    this.description = '',
    this.imagePath,
    this.isActive = true,
  });

  final String name;
  final String barcode;
  final String sku;
  final String categoryId;
  final String unit;
  final double purchasePrice;
  final double sellingPrice;
  final double wholesalePrice;
  final double halfWholesalePrice;
  final double minStock;
  final double openingStock;
  final String? supplierId;
  final String description;
  final String? imagePath;
  final bool isActive;
}

class StockMovement {
  const StockMovement({
    required this.id,
    required this.productId,
    required this.date,
    required this.type,
    required this.qty,
    required this.stockAfter,
    required this.user,
    this.refId,
    this.refNumber,
    this.note = '',
  });

  final String id;
  final String productId;
  final DateTime date;
  final StockMoveType type;

  /// Signed quantity (+ in, - out).
  final double qty;
  final double stockAfter;
  final String? refId;
  final String? refNumber;
  final String note;
  final String user;
}

enum ProductStockFilter { all, low, out, inactive }

enum ProductSort {
  name('الاسم'),
  newest('الأحدث'),
  priceHigh('السعر: الأعلى'),
  priceLow('السعر: الأقل'),
  stockLow('المخزون: الأقل'),
  stockHigh('المخزون: الأكثر');

  const ProductSort(this.label);
  final String label;
}

class ProductQuery {
  const ProductQuery({
    this.search = '',
    this.categoryId,
    this.stockFilter = ProductStockFilter.all,
    this.sort = ProductSort.name,
    this.includeInactive = true,
  });

  final String search;
  final String? categoryId;
  final ProductStockFilter stockFilter;
  final ProductSort sort;
  final bool includeInactive;

  ProductQuery copyWith({
    String? search,
    String? Function()? categoryId,
    ProductStockFilter? stockFilter,
    ProductSort? sort,
  }) =>
      ProductQuery(
        search: search ?? this.search,
        categoryId: categoryId != null ? categoryId() : this.categoryId,
        stockFilter: stockFilter ?? this.stockFilter,
        sort: sort ?? this.sort,
        includeInactive: includeInactive,
      );
}

class ProductStats {
  const ProductStats({
    required this.soldQty,
    required this.soldAmount,
    required this.purchasedQty,
    required this.purchasedAmount,
    required this.returnedQty,
    required this.profit,
    required this.recentMovements,
  });

  final double soldQty;
  final double soldAmount;
  final double purchasedQty;
  final double purchasedAmount;
  final double returnedQty;
  final double profit;
  final List<StockMovement> recentMovements;
}
