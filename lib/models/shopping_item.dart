// A sentinel value to detect if a parameter is passed or not.
const _sentinel = Object();

class ShoppingItem {
  final int? id;
  final String name;
  final double quantity;
  final String unit;
  final double price;
  final String category;
  final int? categoryId;
  final int categoryColor;
  final bool isBought;
  final DateTime? doneTime;
  final double unitPrice;
  final String? imagePath;

  ShoppingItem({
    this.id,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.price,
    required this.category,
    this.categoryId,
    required this.categoryColor,
    this.isBought = false,
    this.doneTime,
    double? unitPrice,
    this.imagePath,
  }) : unitPrice = unitPrice ?? (price / quantity);

  ShoppingItem copyWith({
    int? id,
    String? name,
    double? quantity,
    String? unit,
    double? price,
    String? category,
    Object? categoryId = _sentinel,
    int? categoryColor,
    bool? isBought,
    Object? doneTime = _sentinel,
    double? unitPrice,
    Object? imagePath = _sentinel,
  }) {
    return ShoppingItem(
      id: id ?? this.id,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      price: price ?? this.price,
      category: category ?? this.category,
      categoryId: categoryId == _sentinel ? this.categoryId : categoryId as int?,
      categoryColor: categoryColor ?? this.categoryColor,
      isBought: isBought ?? this.isBought,
      doneTime: doneTime == _sentinel ? this.doneTime : doneTime as DateTime?,
      unitPrice: unitPrice ?? this.unitPrice,
      imagePath: imagePath == _sentinel ? this.imagePath : imagePath as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final map = {
      'name': name,
      'quantity': quantity,
      'unit': unit,
      'price': price,
      'category': category,
      'categoryId': categoryId,
      'categoryColor': categoryColor,
      'isBought': isBought,
      'doneTime': doneTime?.millisecondsSinceEpoch,
      'unitPrice': unitPrice,
      'imagePath': imagePath,
    };
    if (id != null) map['id'] = id;
    return map;
  }

  factory ShoppingItem.fromJson(Map<String, dynamic> json) {
    return ShoppingItem(
      id: json['id'] as int?,
      name: json['name'] as String,
      quantity: (json['quantity'] as num).toDouble(),
      unit: json['unit'] as String,
      price: (json['price'] as num).toDouble(),
      category: json['category'] as String,
      categoryId: json['categoryId'] as int?,
      categoryColor: json['categoryColor'] as int,
      isBought: json['isBought'] as bool,
      doneTime: json['doneTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['doneTime'] as int)
          : null,
      unitPrice: (json['unitPrice'] as num).toDouble(),
      imagePath: json['imagePath'] as String?,
    );
  }

  // Convert from Map (database) to ShoppingItem
  factory ShoppingItem.fromMap(Map<String, dynamic> map) {
    return ShoppingItem(
      id: map['id'] as int?,
      name: map['name'] as String,
      quantity: map['quantity'] as double,
      unit: map['unit'] as String,
      price: map['price'] as double,
      category: map['category_name'] as String,
      categoryId: map['category_id'] as int?,
      isBought: map['status'] == 1,
      doneTime: map['date'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['date'] as int)
          : null,
      categoryColor: map['categoryColor'] as int? ?? 0xFF9E9E9E,
      unitPrice: map['unitPrice'] as double?,
      imagePath: map['imagePath'] as String?,
    );
  }

  // Convert ShoppingItem to Map (for database)
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'quantity': quantity,
      'unit': unit,
      'price': price,
      'status': isBought ? 1 : 0,
      'date': doneTime?.millisecondsSinceEpoch,
      'imagePath': imagePath,
    };
  }
}
