import 'dart:io';
import 'package:flutter/material.dart';
import '../services/category_notifier.dart';
import 'add_category_dialog.dart';
import '../database/database_helper.dart';
import '../models/category.dart';
import '../models/item.dart';
import 'add_new_item_dialog.dart';

class ItemSelectionDialog extends StatefulWidget {
  const ItemSelectionDialog({Key? key}) : super(key: key);

  @override
  _ItemSelectionDialogState createState() => _ItemSelectionDialogState();
}

class _ItemSelectionDialogState extends State<ItemSelectionDialog> {
  List<Item> _items = [];
  List<Item> _filteredItems = [];
  List<Category> _categories = [];
  Category? _selectedCategory;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _categorySearchController = TextEditingController();
  final FocusNode _categoryFocusNode = FocusNode();
  final GlobalKey _categoryAutocompleteKey = GlobalKey();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_filterItems);

    // Rebuild the category search field to show/hide the clear button and handle filter resets.
    _categorySearchController.addListener(() {
      if (mounted) {
        setState(() {
          // This is to rebuild the suffix icon in the fieldViewBuilder.
        });
        if (_categorySearchController.text.isEmpty && _selectedCategory != null) {
          // This part handles when the user manually clears the field by backspacing.
          setState(() {
            _selectedCategory = null;
            _filterItems();
          });
        }
      }
    });

    // Listen for category updates
    CategoryNotifier.instance.addListener(_onCategoryUpdated);
  }

  void _onCategoryUpdated() {
    // When categories are updated, reset selection and reload data.
    if (mounted) {
      setState(() {
        _selectedCategory = null;
        _categorySearchController.clear();
      });
    }
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });
    final dbHelper = DatabaseHelper();
    final results = await Future.wait([
      dbHelper.getItems(),
      dbHelper.getCategories(),
    ]);
    if (mounted) {
      setState(() {
        _items = results[0] as List<Item>;
        _categories = results[1] as List<Category>;
        _isLoading = false;
        _filterItems(); // Re-apply filters with the new data
      });
    }
  }

  void _filterItems() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredItems = _items.where((item) {
        final nameMatches = item.name.toLowerCase().contains(query);
        final categoryMatches = _selectedCategory == null || item.categoryId == _selectedCategory!.id;
        return nameMatches && categoryMatches;
      }).toList();
    });
  }

  Future<void> _addNewItem() async {
    // Await the dialog to close. After it closes, reload the data regardless
    // of the result to ensure the list is always up-to-date.
    await showDialog<Item>(
      context: context,
      builder: (context) => const AddNewItemDialog(),
    );
    await _loadData();
  }

  Future<void> _addNewCategory() async {
    // The dialog now handles database updates and notifies listeners.
    // The refresh is handled by the `_onCategoryUpdated` listener.
    await showAddCategoryDialog(context);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _categorySearchController.dispose();
    _categoryFocusNode.dispose();
    // Clean up the listener
    CategoryNotifier.instance.removeListener(_onCategoryUpdated);
    super.dispose();
  }

  Widget _buildImage(String? path) {
    final placeholder = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Icon(
        Icons.shopping_cart,
        color: Theme.of(context).colorScheme.primary,
        size: 24,
      ),
    );

    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (file.existsSync()) {
        return SizedBox(
          width: 40,
          height: 40,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8.0),
            child: Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => placeholder,
            ),
          ),
        );
      }
    }
    return placeholder;
  }

  Widget _buildCategoryImage(Category category) {
    final placeholder = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Icon(
        Icons.category,
        color: Colors.grey.shade600,
        size: 24,
      ),
    );

    if (category.imagePath != null && category.imagePath!.isNotEmpty) {
      final file = File(category.imagePath!);
      if (file.existsSync()) {
        return SizedBox(
          width: 40,
          height: 40,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8.0),
            child: Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => placeholder,
            ),
          ),
        );
      }
    }
    return placeholder;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select an Item'),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.6,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RawAutocomplete<Category>(
                    key: _categoryAutocompleteKey,
                    textEditingController: _categorySearchController,
                    focusNode: _categoryFocusNode,
                    displayStringForOption: (Category option) => option.name,
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text.isEmpty) {
                        return _categories;
                      }
                      return _categories.where((Category category) {
                        return category.name.toLowerCase().contains(textEditingValue.text.toLowerCase());
                      });
                    },
                    onSelected: (Category selection) {
                      if (mounted) {
                        setState(() {
                          _selectedCategory = selection;
                          _categorySearchController.text = selection.name;
                          _filterItems();
                        });
                      }
                    },
                    fieldViewBuilder: (BuildContext context, TextEditingController fieldTextEditingController, FocusNode fieldFocusNode, VoidCallback onFieldSubmitted) {
                      return TextFormField(
                        controller: fieldTextEditingController,
                        focusNode: fieldFocusNode,
                        decoration: InputDecoration(
                          labelText: 'Search Category',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _categorySearchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    if (mounted) {
                                      setState(() {
                                        _selectedCategory = null;
                                        fieldTextEditingController.clear();
                                        _filterItems();
                                        fieldFocusNode.unfocus();
                                      });
                                    }
                                  },
                                )
                              : null,
                        ),
                      );
                    },
                    optionsViewBuilder: (BuildContext context, AutocompleteOnSelected<Category> onSelected, Iterable<Category> options) {
                      final RenderBox? fieldRenderBox = _categoryAutocompleteKey.currentContext?.findRenderObject() as RenderBox?;
                      final double fieldWidth = fieldRenderBox?.size.width ?? 300; // Default width as a fallback

                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4.0,
                          child: SizedBox(
                            width: fieldWidth,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 250),
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: options.length + 2, // +2 for "All" and "Add New"
                                itemBuilder: (BuildContext context, int index) {
                                  if (index == 0) {
                                    // "All Categories" option
                                    return ListTile(
                                      leading: const Icon(Icons.clear_all),
                                      title: const Text('All Categories'),
                                      onTap: () {
                                        if (mounted) {
                                          setState(() {
                                            _selectedCategory = null;
                                            _categorySearchController.clear();
                                            _filterItems();
                                            _categoryFocusNode.unfocus();
                                          });
                                        }
                                      },
                                    );
                                  }
                                  if (index == 1) {
                                    // "Add New Category" button
                                    return ListTile(
                                      leading: const Icon(Icons.add_circle_outline),
                                      title: const Text('Add New Category'),
                                      onTap: () {
                                        _categoryFocusNode.unfocus();
                                        _addNewCategory();
                                      },
                                    );
                                  }
                                  final Category option = options.elementAt(index - 2);
                                  return ListTile(
                                    leading: _buildCategoryImage(option),
                                    title: Text(option.name),
                                    onTap: () {
                                      onSelected(option);
                                      _categoryFocusNode.unfocus();
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'Search Items',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Scrollbar(
                      thumbVisibility: true, // Always show scrollbar
                      child: _filteredItems.isEmpty
                          ? const Center(child: Text('No items found.'))
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: _filteredItems.length,
                              itemBuilder: (context, index) {
                                final item = _filteredItems[index];
                                return ListTile(
                                  leading: _buildImage(item.imagePath),
                                  title: Text(item.name),
                                  subtitle: Text('Price: ${item.price}'),
                                  onTap: () {
                                    Navigator.of(context).pop(item);
                                  },
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: _addNewCategory,
                  icon: const Icon(Icons.category_outlined, color: Colors.blue),
                  tooltip: 'New Category',
                ),
                const Text('New Category', style: TextStyle(fontSize: 12)),
              ],
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: _addNewItem,
                  icon: const Icon(Icons.add_box_outlined, color: Colors.green),
                  tooltip: 'New Item',
                ),
                const Text('New Item', style: TextStyle(fontSize: 12)),
              ],
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                  tooltip: 'Cancel',
                ),
                const Text('Cancel', style: TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
