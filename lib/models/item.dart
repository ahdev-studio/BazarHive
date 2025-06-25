class Item {
  final int? id;
  final String name;
  final int categoryId;
  final double price;
  final String? imagePath;

  Item({
    this.id,
    required this.name,
    required this.categoryId,
    required this.price,
    this.imagePath,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'categoryId': categoryId,
      'price': price,
      'imagePath': imagePath,
    };
  }

  Item copyWith({
    int? id,
    String? name,
    int? categoryId,
    double? price,
    String? imagePath,
  }) {
    return Item(
      id: id ?? this.id,
      name: name ?? this.name,
      categoryId: categoryId ?? this.categoryId,
      price: price ?? this.price,
      imagePath: imagePath ?? this.imagePath,
    );
  }

  factory Item.fromMap(Map<String, dynamic> map) {
    return Item(
      id: map['id'],
      name: map['name'],
      categoryId: map['categoryId'],
      price: map['price'],
      imagePath: map['imagePath'],
    );
  }
}
