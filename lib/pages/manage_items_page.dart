import 'dart:io';
import 'package:BazarHive/database/database_helper.dart';
import 'package:BazarHive/models/category.dart';
import 'package:BazarHive/models/item.dart';
import 'package:BazarHive/widgets/add_new_item_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:BazarHive/providers/currency_provider.dart';

class ManageItemsPage extends StatefulWidget {
  const ManageItemsPage({super.key});

  @override
  State<ManageItemsPage> createState() => _ManageItemsPageState();
}

class _ManageItemsPageState extends State<ManageItemsPage> {
  Map<int, List<Item>> _groupedItems = {};
  Map<int, Category> _categories = {};
  Map<int, bool> _isExpanded = {};
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final dbHelper = DatabaseHelper();
    final items = await dbHelper.getItems();
    final categoriesList = await dbHelper.getCategories();

    final Map<int, Category> categories = {
      for (var cat in categoriesList.where((c) => c.id != null)) cat.id!: cat
    };
    final groupedItems = <int, List<Item>>{};

    for (final item in items) {
      // Ensure the category for the item exists before grouping
      if (categories.containsKey(item.categoryId)) {
        if (groupedItems.containsKey(item.categoryId)) {
          groupedItems[item.categoryId]!.add(item);
        } else {
          groupedItems[item.categoryId] = [item];
        }
      }
    }

    final sortedCategoryIds = categories.keys.toList()
      ..sort((a, b) => categories[a]!.name.compareTo(categories[b]!.name));

    final sortedGroupedItems = {
      for (var id in sortedCategoryIds) id: groupedItems[id] ?? []
    };

    final expandedState = {for (var id in sortedCategoryIds) id: false};

    setState(() {
      _categories = categories;
      _groupedItems = sortedGroupedItems;
      _isExpanded = expandedState;
      _isLoading = false;
    });
  }

  Widget _buildItemImage(String? imagePath) {
    if (imagePath == null || imagePath.isEmpty) {
      return Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: Icon(
          Icons.shopping_cart,
          color: Theme.of(context).colorScheme.primary,
          size: 30,
        ),
      );
    }

    final imageFile = File(imagePath);
    if (!imageFile.existsSync()) {
      return Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: const Icon(Icons.broken_image, color: Colors.grey),
      );
    }

    return SizedBox(
      width: 60,
      height: 60,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8.0),
        child: Image.file(
          imageFile,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: const Icon(Icons.broken_image, color: Colors.grey),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currencyProvider = Provider.of<CurrencyProvider>(context);

    final Map<int, List<Item>> filteredItems = _searchQuery.isEmpty
        ? _groupedItems
        : Map.fromEntries(_groupedItems.entries.map((entry) {
            final matchingItems = entry.value
                .where((item) =>
                    item.name.toLowerCase().contains(_searchQuery))
                .toList();
            return MapEntry(entry.key, matchingItems);
          }).where((entry) => entry.value.isNotEmpty));

    final categoryIds = filteredItems.keys.toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        title: const Text(
          'Manage Items',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search items...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                    ),
                  ),
                ),
                if (filteredItems.isEmpty && !_isLoading)
                  const Expanded(
                    child: Center(
                      child: Text('No items found.'),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      itemCount: categoryIds.length,
                      itemBuilder: (context, index) {
                        final categoryId = categoryIds[index];
                        final category = _categories[categoryId];
                        final itemsInCategory = filteredItems[categoryId]!;

                        if (category == null) {
                          return const SizedBox.shrink();
                        }

                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          clipBehavior: Clip.antiAlias,
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Theme(
                            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              backgroundColor: category.color.withOpacity(0.2),
                              collapsedBackgroundColor: category.color.withOpacity(0.2),
                              key: ValueKey<String>('$categoryId-${_searchQuery.isNotEmpty}'),
                              leading: CircleAvatar(
                                radius: 22,
                                backgroundColor: category.color.withAlpha(200),
                                backgroundImage: (category.imagePath != null && File(category.imagePath!).existsSync())
                                    ? FileImage(File(category.imagePath!))
                                    : null,
                                child: (category.imagePath == null || !File(category.imagePath!).existsSync())
                                    ? Text(
                                        category.name.isNotEmpty ? category.name[0].toUpperCase() : '',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                      )
                                    : null,
                              ),
                              title: Text(
                                category.name,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              initiallyExpanded: _searchQuery.isNotEmpty || (_isExpanded[categoryId] ?? false),
                              onExpansionChanged: (bool expanded) {
                                if (_searchQuery.isEmpty) {
                                  setState(() {
                                    _isExpanded[categoryId] = expanded;
                                  });
                                }
                              },
                              children: itemsInCategory.map((item) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                                  child: Card(
                                    elevation: 1,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      leading: _buildItemImage(item.imagePath),
                                      title: Text(
                                        item.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      subtitle: Text(
                                        'Price: ${currencyProvider.selectedCurrencySymbol}${item.price}',
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit),
                                            onPressed: () async {
                                              await showDialog(
                                                context: context,
                                                builder: (context) => AddNewItemDialog(itemToEdit: item),
                                              );
                                              _loadData();
                                            },
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete),
                                            onPressed: () async {
                                              final confirm = await showDialog<bool>(
                                                context: context,
                                                builder: (context) => AlertDialog(
                                                  title: const Text('Confirm Delete'),
                                                  content: Text('Are you sure you want to delete "${item.name}"?'),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () => Navigator.of(context).pop(false),
                                                      child: const Text('Cancel'),
                                                    ),
                                                    TextButton(
                                                      onPressed: () => Navigator.of(context).pop(true),
                                                      child: const Text('Delete'),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (confirm == true) {
                                                await DatabaseHelper().deleteItem(item.id!);
                                                _loadData();
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await showDialog(
            context: context,
            builder: (context) => const AddNewItemDialog(),
          );
          _loadData();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
