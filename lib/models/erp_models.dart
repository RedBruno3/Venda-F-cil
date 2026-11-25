class StoreModel {
  final String id;
  final String name;
  final String role;

  StoreModel({
    required this.id,
    required this.name,
    required this.role,
  });

  bool get isAdmin => role == 'admin';
}

class ProductModel {
  final String id;
  final String storeId;
  final String code;
  final String name;
  final double price;
  final int stock;
  final int minStock;

  ProductModel({
    required this.id,
    required this.storeId,
    required this.code,
    required this.name,
    required this.price,
    required this.stock,
    required this.minStock,
  });

  bool get isLowStock => stock <= minStock;

  factory ProductModel.fromMap(Map<String, dynamic> map) {
    return ProductModel(
      id: map['id'] as String,
      storeId: map['store_id'] as String,
      code: map['code'] as String,
      name: map['name'] as String,
      price: (map['price'] as num).toDouble(),
      stock: (map['stock'] as num).toInt(),
      minStock: (map['min_stock'] as num).toInt(),
    );
  }
}

class CartItem {
  final ProductModel product;
  int quantity;

  CartItem({required this.product, this.quantity = 1});

  double get subtotal => product.price * quantity;
}

class SaleItemModel {
  final String productCode;
  final String productName;
  final int quantity;
  final double unitPrice;

  SaleItemModel({
    required this.productCode,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
  });

  factory SaleItemModel.fromMap(Map<String, dynamic> map) {
    return SaleItemModel(
      productCode: map['product_code'] as String,
      productName: map['product_name'] as String,
      quantity: (map['quantity'] as num).toInt(),
      unitPrice: (map['unit_price'] as num).toDouble(),
    );
  }
}

class SaleModel {
  final String id;
  final String paymentMethod;
  final double total;
  final String status;
  final DateTime createdAt;
  final List<SaleItemModel> items;

  SaleModel({
    required this.id,
    required this.paymentMethod,
    required this.total,
    required this.status,
    required this.createdAt,
    required this.items,
  });

  bool get isCanceled => status == 'canceled';

  DateTime get createdAtBrasilia => createdAt.toUtc().subtract(const Duration(hours: 3));

  factory SaleModel.fromMap(Map<String, dynamic> map) {
    final rawItems = (map['sale_items'] as List<dynamic>? ?? []);
    return SaleModel(
      id: map['id'] as String,
      paymentMethod: map['payment_method'] as String,
      total: (map['total'] as num).toDouble(),
      status: map['status'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      items: rawItems.map((e) => SaleItemModel.fromMap(e as Map<String, dynamic>)).toList(),
    );
  }
}
