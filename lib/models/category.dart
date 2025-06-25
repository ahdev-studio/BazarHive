import 'package:flutter/material.dart';

class Category {
  final int? id;
  String name;
  Color color;
  String? imagePath;
  int get colorValue => color.value;

  Category({
    this.id,
    required this.name,
    required this.color,
    this.imagePath,
  });

  // Create a Category from a database map
  factory Category.fromMap(Map<String, dynamic> map) {
    final colorValue = map['color'];
    Color color;
    
    if (colorValue is String) {
      // Handle legacy string color format
      color = Color(int.parse(colorValue));
    } else if (colorValue is int) {
      color = Color(colorValue);
    } else {
      throw FormatException('Invalid color format: $colorValue');
    }
    
    return Category(
      id: map['id'] as int?,
      name: map['name'] as String,
      color: color,
      imagePath: map['imagePath'] as String?,
    );
  }

  // Convert Category to a database map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'color': color.value,
      'imagePath': imagePath,
    };
  }

  Map<String, dynamic> toJson() => toMap();

  // Create a copy of this Category with given fields replaced with new values
  Category copyWith({
    int? id,
    String? name,
    Color? color,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
    );
  }
}
