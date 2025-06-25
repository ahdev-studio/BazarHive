import 'package:flutter/material.dart';
import 'package:BazarHive/models/category.dart' as models;
import 'package:BazarHive/models/shopping_item.dart';
import 'package:BazarHive/database/database_helper.dart';
import 'package:BazarHive/widgets/edit_item_dialog.dart';
import 'dart:io';
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'widgets/banner_ad_widget.dart';
import 'package:BazarHive/providers/currency_provider.dart';
import 'package:BazarHive/services/ad_helper.dart';

class BoughtItemsPage extends StatefulWidget {
  const BoughtItemsPage({super.key});

  @override
  State<BoughtItemsPage> createState() => _BoughtItemsPageState();
}

class _BoughtItemsPageState extends State<BoughtItemsPage> {
  Map<String, models.Category> _categories = <String, models.Category>{};
  Map<String, bool> _categoryFilters = <String, bool>{};
  Set<String> _selectedCategories = {};
  final DatabaseHelper _databaseHelper = DatabaseHelper();
  List<ShoppingItem> _boughtItems = [];
  Map<String, List<ShoppingItem>> _groupedItems = {};
  DateTime? _selectedDate;
  
  // Interstitial ad helper
  final InterstitialAdHelper _adHelper = InterstitialAdHelper();

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadBoughtItems();
    
    // Load the interstitial ad
    _adHelper.loadAd();
  }

  Future<void> _loadCategories() async {
    final db = await _databaseHelper.database;
    final List<Map<String, dynamic>> maps = await db.query('categories');

    setState(() {
      _categories = {
        for (var map in maps)
          map['name'] as String: models.Category(
            id: map['id'] as int,
            name: map['name'] as String,
            color: Color(map['color'] as int),
          ),
      };
      _categoryFilters = {
        for (var map in maps)
          map['name'] as String: false,
      };
    });
  }

  Future<void> _loadBoughtItems() async {
    List<Map<String, dynamic>> items;
    if (_selectedDate != null) {
      items = await _databaseHelper.getBoughtItemsByDate(_selectedDate!);
    } else {
      items = await _databaseHelper.getBoughtItems();
    }

    final loadedItems = items.map((item) => ShoppingItem(
      id: item['id'] as int,
      name: item['name'] as String,
      quantity: item['quantity'] is int ? (item['quantity'] as int).toDouble() : item['quantity'] as double,
      unit: item['unit'] as String,
      price: item['price'] is int ? (item['price'] as int).toDouble() : item['price'] as double,
      category: item['category_name'] as String, // Corrected column name
      categoryId: item['category_id'] as int?,
      categoryColor: item['categoryColor'] as int,
      unitPrice: item['unitPrice'] is int ? (item['unitPrice'] as int).toDouble() : item['unitPrice'] as double,
      imagePath: item['imagePath'] as String?,
      isBought: true,
      doneTime: DateTime.fromMillisecondsSinceEpoch(item['date'] as int), // Corrected column name
    )).toList();

    setState(() {
      if (_selectedCategories.isEmpty) {
        _boughtItems = loadedItems;
        _groupedItems = _groupItemsByCategory(loadedItems);
      } else {
        final filteredItems = loadedItems
            .where((item) => _selectedCategories.contains(item.category))
            .toList();
        _boughtItems = filteredItems;
        _groupedItems = _groupItemsByCategory(filteredItems);
      }
    });
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _loadBoughtItems();
    }
  }

  Future<void> _editItem(ShoppingItem item) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => EditItemDialog(
        item: item,
        categories: _categories,
      ),
    );

    if (result != null) {
      final double quantity = result['quantity'] as double;
      final double unitPrice = result['unitPrice'] as double;

      // Construct the complete map for the database update
      final Map<String, dynamic> dataToUpdate = {
        'name': item.name, // Name is not editable from this dialog
        'quantity': quantity,
        'unit': item.unit, // Unit is not editable
        'price': quantity * unitPrice,
        'category_name': result['category'] as String,
        'category_id': result['categoryId'] as int?, // Crucial: Must be returned from EditItemDialog
        'categoryColor': result['categoryColor'] as int,
        'unitPrice': unitPrice,
        'imagePath': result['imagePath'] as String?,
        'date': (result['doneTime'] as DateTime?)?.millisecondsSinceEpoch,
      };

      // Update in database
      await _databaseHelper.updateBoughtItem(item.id!, dataToUpdate);

      _loadBoughtItems(); // Refresh the list
    }
  }

  Map<String, List<ShoppingItem>> _groupItemsByCategory(List<ShoppingItem> items) {
    final grouped = <String, List<ShoppingItem>>{};
    for (final item in items) {
      if (!grouped.containsKey(item.category)) {
        grouped[item.category] = [];
      }
      grouped[item.category]!.add(item);
    }
    // Sort categories alphabetically
    return Map.fromEntries(
      grouped.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  Future<bool> _requestStoragePermission() async {
    try {
      if (Platform.isAndroid) {
        if (await Permission.storage.request().isGranted &&
            await Permission.manageExternalStorage.request().isGranted) {
          return true;
        }
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('Permission error: $e');
      return false;
    }
  }

  Future<String> _createSpendHiveDirectory() async {
    try {
      final dirPath = '/storage/emulated/0/Download/SpendHive by AHDS/BazarHive';
      final spendHiveDir = Directory(dirPath);
      if (!await spendHiveDir.exists()) {
        await spendHiveDir.create(recursive: true);
      }
      return dirPath;
    } catch (e) {
      debugPrint('Directory creation error: $e');
      rethrow;
    }
  }

  // Show interstitial ad
  Future<void> _showInterstitialAd() async {
    try {
      // Only show ad if it's loaded
      if (_adHelper.isAdLoaded) {
        // Add a small delay to ensure UI operations complete first
        await Future.delayed(const Duration(milliseconds: 500));
        await _adHelper.showAdIfLoaded();
      } else {
        // If ad is not loaded, try to load it for next time
        _adHelper.loadAd();
        debugPrint('Interstitial ad not loaded yet, loading for next time');
      }
    } catch (e) {
      debugPrint('Error showing interstitial ad: $e');
    }
  }

  Future<void> _exportToSpendHive(List<ShoppingItem> selectedItems) async {
    try {
      // Permission already checked in _showExportDialog
      final dirPath = await _createSpendHiveDirectory();

      final exportDate = _selectedDate ?? DateTime.now();
      final fileName = 'bazar_export_${DateFormat('yyyyMMdd').format(exportDate)}.json';
      final file = File('$dirPath/$fileName');

      final exportData = selectedItems.map((item) => {
        'description': item.name,
        'amount': item.price,
        'quantity': item.quantity,
        'time': DateFormat('hh:mm a').format(item.doneTime!)
      }).toList();

      await file.writeAsString(jsonEncode(exportData));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Export successful to SpendHive!'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Show interstitial ad after successful export
        _showInterstitialAd();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showExportDialog() async {
    // Request storage permission first
    final hasPermission = await _requestStoragePermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Storage permission is required to export data'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    
    final selectedItems = <ShoppingItem>{};
    bool selectAll = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Send to SpendHive'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Select All checkbox
                CheckboxListTile(
                  title: const Text('Select All',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  value: selectAll,
                  onChanged: (bool? value) {
                    setState(() {
                      selectAll = value ?? false;
                      if (selectAll) {
                        selectedItems.addAll(_boughtItems);
                      } else {
                        selectedItems.clear();
                      }
                    });
                  },
                ),
                const Divider(),
                for (var item in _boughtItems)
                  CheckboxListTile(
                    title: Text(item.name),
                    subtitle: Consumer<CurrencyProvider>(
                      builder: (context, currencyProvider, child) => Text(
                        '${currencyProvider.selectedCurrency.symbol}${item.price.toStringAsFixed(2)} - ${item.quantity} ${item.unit} - ${DateFormat('hh:mm a').format(item.doneTime!)}'
                      ),
                    ),
                    value: selectedItems.contains(item),
                    onChanged: (bool? value) {
                      setState(() {
                        if (value == true) {
                          selectedItems.add(item);
                          if (selectedItems.length == _boughtItems.length) {
                            selectAll = true;
                          }
                        } else {
                          selectedItems.remove(item);
                          selectAll = false;
                        }
                      });
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (_selectedDate == null) {
                  Navigator.of(context).pop(); // Close the dialog
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select a date first.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                Navigator.of(context).pop();
                if (selectedItems.isNotEmpty) {
                  _exportToSpendHive(selectedItems.toList());
                }
              },
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemImage(ShoppingItem item) {
    if (item.imagePath == null || item.imagePath!.isEmpty) {
      return Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: Color(item.categoryColor).withOpacity(0.1),
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Icon(
          Icons.shopping_cart,
          color: Color(item.categoryColor),
          size: 30,
        ),
      );
    }

    final imageFile = File(item.imagePath!);
    if (!imageFile.existsSync()) {
      return Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: const Icon(Icons.broken_image, color: Colors.grey),
      );
    }

    return SizedBox(
      width: 60,
      height: 60,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.0),
        child: Image.file(
          imageFile,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: const Icon(Icons.broken_image, color: Colors.grey),
            );
          },
        ),
      ),
    );
  }

  Future<void> _deleteItem(ShoppingItem item) async {
    if (item.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot delete item: ID is missing'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item'),
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
    ) ?? false;

    if (confirmed) {
      try {
        await _databaseHelper.deleteBoughtItems([item.id!]);
        await _loadBoughtItems(); // Reload items from database
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Item deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        debugPrint('Error deleting item: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete item: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    // Dispose the ad when the page is disposed
    _adHelper.dispose();
    super.dispose();
  }

  double _calculateTotalAmount() {
    return _boughtItems.fold(0.0, (sum, item) => sum + item.price);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        title: const Text(
          'Bought Items',
          style: TextStyle(color: Colors.white),
        ),
        actions: [],
      ),
      body: Column(
        children: [
          // Summary Section
          Container(
            margin: const EdgeInsets.all(8.0),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Theme.of(context).cardColor
                  : Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).shadowColor.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total Items',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _boughtItems.length.toString(),
                      style: TextStyle(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.blue.shade300
                            : Colors.blue.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Total Amount',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Consumer<CurrencyProvider>(
                      builder: (context, currencyProvider, child) {
                        return Text(
                          '${currencyProvider.selectedCurrency.symbol}${_calculateTotalAmount().toStringAsFixed(2)}',
                          style: TextStyle(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Colors.green.shade300
                                : Colors.green.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: TextButton.icon(
              onPressed: () {
                if (_selectedDate == null) {
                  showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        title: const Text('Attention'),
                        content: const Text('Please select a date range to send data.'),
                        actions: <Widget>[
                          TextButton(
                            child: const Text('OK'),
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                          ),
                        ],
                      );
                    },
                  );
                } else {
                  _showExportDialog();
                }
              },
              icon: Image.asset(
                'assets/images/SpendHive.png',
                width: 24,
                height: 24,
              ),
              label: const Text('Send to SpendHive'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          // Filter Section
          Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  spreadRadius: 1,
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.calendar_today),
                      label: const Text('Select Date'),
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (date != null) {
                          setState(() => _selectedDate = date);
                          _loadBoughtItems();
                        }
                      },
                    ),
                    if (_selectedDate != null)
                      Text(
                        '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}',
                        style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    const Spacer(),
                    StatefulBuilder(
                      builder: (BuildContext context, StateSetter menuSetState) {
                        return PopupMenuButton<String>(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _selectedCategories.isEmpty
                                    ? 'Categories'
                                    : '${_selectedCategories.length} Selected',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              const Icon(Icons.arrow_drop_down),
                            ],
                          ),
                          onSelected: (String value) {
                            // This logic is now handled in the onTap of CheckedPopupMenuItem, 
                            // but we keep onSelected for the 'clear' action.
                            if (value == 'clear') {
                              menuSetState(() {
                                _selectedCategories.clear();
                              });
                              setState(() {}); // Update the main page UI
                              _loadBoughtItems();
                            }
                          },
                          itemBuilder: (BuildContext context) {
                            var items = <PopupMenuEntry<String>>[];
                            items.addAll(
                              _categories.keys.map((String categoryName) {
                                final categoryColor =
                                    _categories[categoryName]?.color.value ??
                                        Colors.grey.value;
                                return CheckedPopupMenuItem<String>(
                                  value: categoryName,
                                  checked: _selectedCategories.contains(categoryName),
                                  onTap: () { // Use onTap for selection
                                    menuSetState(() {
                                      if (_selectedCategories.contains(categoryName)) {
                                        _selectedCategories.remove(categoryName);
                                      } else {
                                        _selectedCategories.add(categoryName);
                                      }
                                    });
                                    setState(() {}); // Update the main page UI
                                    _loadBoughtItems();
                                  },
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 16,
                                        height: 16,
                                        margin: const EdgeInsets.only(right: 8),
                                        decoration: BoxDecoration(
                                          color: Color(categoryColor),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      Text(categoryName),
                                    ],
                                  ),
                                );
                              }),
                            );

                            if (_selectedCategories.isNotEmpty) {
                              items.add(const PopupMenuDivider());
                              items.add(
                                const PopupMenuItem<String>(
                                  value: 'clear',
                                  child: Text('Clear Filters'),
                                ),
                              );
                            }
                            return items;
                          },
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const BannerAdWidget(),
              ],
            ),
          ),

          if (_groupedItems.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'No bought items found',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _groupedItems.length,
                itemBuilder: (context, index) {
                  final category = _groupedItems.keys.elementAt(index);
                  final items = _groupedItems[category]!;
                  final categoryColor = items.isNotEmpty ? Color(items.first.categoryColor) : Colors.grey;
                  final categoryTotal = items.fold<double>(0, (sum, item) => sum + item.price);

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        backgroundColor: categoryColor.withOpacity(0.2),
                        collapsedBackgroundColor: categoryColor.withOpacity(0.2),
                        title: Consumer<CurrencyProvider>(
                          builder: (context, currencyProvider, child) {
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Text(category, style: const TextStyle(fontWeight: FontWeight.bold)),
                                ),
                                Text(
                                  '${currencyProvider.selectedCurrency.symbol}${categoryTotal.toStringAsFixed(2)}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            );
                          },
                        ),
                        children: items.map((item) {
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ListTile(
                              leading: Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: Color(item.categoryColor).withOpacity(0.1),
                                ),
                                child: _buildItemImage(item),
                              ),
                              title: Text(
                                item.name,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(item.categoryColor),
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(Icons.format_list_numbered, size: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'Quantity: ${item.quantity} ${item.unit}',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Theme.of(context).colorScheme.onSurface,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(Icons.monetization_on, size: 14, color: Color(item.categoryColor)),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Consumer<CurrencyProvider>(
                                          builder: (context, currencyProvider, child) => Text(
                                            'Total: ${currencyProvider.selectedCurrency.symbol}${item.price.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: Color(item.categoryColor),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Icon(Icons.calendar_today, size: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          '${item.doneTime!.day}/${item.doneTime!.month}/${item.doneTime!.year} '
                                          '${item.doneTime!.hour > 12 ? item.doneTime!.hour - 12 : item.doneTime!.hour}:${item.doneTime!.minute.toString().padLeft(2, '0')} ${item.doneTime!.hour >= 12 ? 'PM' : 'AM'}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: PopupMenuButton<String>(
                                icon: Icon(Icons.more_vert, color: Color(item.categoryColor)),
                                onSelected: (String value) {
                                  switch (value) {
                                    case 'edit':
                                      _editItem(item);
                                      break;
                                    case 'delete':
                                      _deleteItem(item);
                                      break;
                                  }
                                },
                                itemBuilder: (BuildContext context) => [
                                  PopupMenuItem<String>(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit, color: Color(item.categoryColor)),
                                        const SizedBox(width: 8),
                                        Text('Edit', style: TextStyle(color: Color(item.categoryColor))),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem<String>(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete, color: Colors.red),
                                        const SizedBox(width: 8),
                                        const Text('Delete', style: TextStyle(color: Colors.red)),
                                      ],
                                    ),
                                  ),
                                ],
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
    );
  }
}
