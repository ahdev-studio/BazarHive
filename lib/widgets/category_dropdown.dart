import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/category.dart';

class CategoryDropdown extends StatefulWidget {
  final void Function(Category?) onCategorySelected;
  final int? initialCategoryId;
  // Create a static key to access the state
  static final GlobalKey<_CategoryDropdownState> globalKey = GlobalKey<_CategoryDropdownState>();

  // Removed const keyword since we're using a non-constant value (globalKey)
  CategoryDropdown({
    Key? key,
    required this.onCategorySelected,
    this.initialCategoryId,
  }) : super(key: key ?? globalKey);

  @override
  State<CategoryDropdown> createState() => _CategoryDropdownState();
  
  // Create a static method to access the state
  static void reloadCategories(BuildContext context) {
    // Try to get the state using the global key first
    final state = globalKey.currentState;
    if (state != null) {
      state._loadCategories();
      return;
    }
    
    // Fallback to findAncestorStateOfType if global key approach fails
    final ancestorState = context.findAncestorStateOfType<_CategoryDropdownState>();
    if (ancestorState != null) {
      ancestorState._loadCategories();
    }
  }
}

class _CategoryDropdownState extends State<CategoryDropdown> {
  Category? selectedCategory;
  List<Category> categories = [];
  bool isLoading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      setState(() {
        isLoading = true;
        error = null;
      });

      final dbHelper = DatabaseHelper();
      final fetchedCategories = await dbHelper.getCategories();
      
      setState(() {
        categories = fetchedCategories;
        if (widget.initialCategoryId != null) {
          try {
            selectedCategory = categories.firstWhere((cat) => cat.id == widget.initialCategoryId);
          } catch (e) {
            selectedCategory = null; // Handle case where ID is not found
          }
        } else {
          selectedCategory = null;
        }
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        error = 'Failed to load categories: $e';
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
        height: 48,
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (error != null) {
      return Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                error!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadCategories,
              tooltip: 'Retry',
            ),
          ],
        ),
      );
    }

    if (categories.isEmpty) {
      return Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('No categories'),
          ],
        ),
      );
    }

    return DropdownButtonFormField<Category>(
      value: selectedCategory,
      decoration: const InputDecoration(
        labelText: 'Category',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      items: categories.map((category) {
        return DropdownMenuItem<Category>(
          value: category,
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: category.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(category.name),
            ],
          ),
        );
      }).toList(),
      onChanged: (Category? value) {
        setState(() {
          selectedCategory = value;
        });
        widget.onCategorySelected(value);
      },
    );
  }
}
