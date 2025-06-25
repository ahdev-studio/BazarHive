import 'dart:io';
import 'package:flutter/material.dart';
import 'widgets/banner_ad_widget.dart';
import 'database/database_helper.dart';
import 'package:BazarHive/services/category_notifier.dart';
import 'package:BazarHive/widgets/add_category_dialog.dart';
import 'models/category.dart';

class CategoryManagementPage extends StatefulWidget {
  const CategoryManagementPage({super.key});

  // Static method to reload categories in any open CategoryManagementPage instances
  static void reloadCategories(BuildContext context) {
    final state = context.findAncestorStateOfType<_CategoryManagementPageState>();
    if (state != null) {
      state._loadCategories();
    }
  }

  // Shared preset colors for consistent color selection across the app
  static const List<Color> presetColors = [
    Color(0xFFE74C3C), // Tomato Red
    Color(0xFFF39C12), // Sunset Orange
    Color(0xFFF1C40F), // Lemon Yellow
    Color(0xFF2ECC71), // Emerald Green
    Color(0xFF1ABC9C), // Mint Green
    Color(0xFF3498DB), // Sky Blue
    Color(0xFF2980B9), // Royal Blue
    Color(0xFF9B59B6), // Purple
    Color(0xFFE91E63), // Deep Pink
    Color(0xFF95A5A6), // Soft Grey
    Color(0xFF8D6E63), // Warm Brown
    Color(0xFF2C3E50), // Charcoal Black
  ];

  @override
  State<CategoryManagementPage> createState() => _CategoryManagementPageState();
}

class _CategoryManagementPageState extends State<CategoryManagementPage> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Category> categories = [];
  List<Category> filteredCategories = [];
  bool isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCategories();
    CategoryNotifier.instance.addListener(_onCategoryUpdated);
    _searchController.addListener(() {
      _filterCategories();
    });
  }

  void _onCategoryUpdated() {
    _loadCategories();
  }

  void _filterCategories() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      filteredCategories = categories.where((category) {
        return category.name.toLowerCase().contains(query);
      }).toList();
    });
  }

  Future<void> _loadCategories() async {
    try {
      final loadedCategories = await _dbHelper.getCategories();
      setState(() {
        categories = loadedCategories;
        filteredCategories = loadedCategories; // Initially, show all categories
        isLoading = false;
      });
    } catch (e) {
      print('Error loading categories: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  // Edit an existing category
  Future<void> _editCategory(Category category) async {
    debugPrint('Opening edit dialog for category: id=${category.id}, name=${category.name}, color=0x${category.color.value.toRadixString(16).toUpperCase()}');
    
    await showAddCategoryDialog(context, categoryToEdit: category);
    // No need to call _loadCategories() here, the listener will handle it.
  }

  // Show confirmation dialog before deleting a category
  Future<void> _showDeleteConfirmation(Category category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text(
          'Are you sure you want to delete "${category.name}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && category.id != null) {
      await _dbHelper.deleteCategory(category.id!);
      CategoryNotifier.instance.notify(); // Notify listeners to refresh
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        title: const Text(
          'Manage Categories',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search Categories',
                hintText: 'Enter category name...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Expanded(
            child: filteredCategories.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.category_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No categories yet',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap the + button to add a category',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: filteredCategories.length,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemBuilder: (context, index) {
                      final category = filteredCategories[index];
                      return Card(
                        color: category.color.withOpacity(0.2),
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: category.imagePath == null ? category.color : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                            child: category.imagePath != null
                                ? ClipOval(
                                    child: Container(
                                      color: Colors.white, // White background for transparent PNGs
                                      child: Image.file(
                                        File(category.imagePath!),
                                        width: 40,
                                        height: 40,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          // If image fails to load, show colored circle
                                          return Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              color: category.color,
                                              shape: BoxShape.circle,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                          title: Text(category.name),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () => _editCategory(category),
                                tooltip: 'Edit category',
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () => _showDeleteConfirmation(category),
                                tooltip: 'Delete category',
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          const BannerAdWidget(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showAddCategoryDialog(context);
          // The listener will automatically handle the refresh.
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
