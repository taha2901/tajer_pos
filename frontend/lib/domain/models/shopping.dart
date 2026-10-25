/// An entry on the shortages list: something to order from a supplier.
/// Either a known product ([productId]) or a free-text name.
class ShoppingItem {
  const ShoppingItem({
    required this.id,
    required this.name,
    required this.qty,
    required this.createdAt,
    this.productId,
    this.unit = '',
    this.stock,
    this.supplierId,
    this.supplierName,
    this.note = '',
    this.addedBy = '',
  });

  final String id;
  final String? productId;
  final String name;
  final String unit;
  final double qty;

  /// Current stock of the product (null for free-text items).
  final double? stock;

  /// Null = can be ordered from any supplier.
  final String? supplierId;
  final String? supplierName;
  final String note;
  final String addedBy;
  final DateTime createdAt;

  bool get isNewProduct => productId == null;
}

class ShoppingItemInput {
  const ShoppingItemInput({this.productId, this.name = '', this.unit = '', required this.qty, this.supplierId, this.note = ''});

  final String? productId;
  final String name;
  final String unit;
  final double qty;
  final String? supplierId;
  final String note;
}
