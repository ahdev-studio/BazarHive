import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/item.dart'; // Import the Item model
import '../models/category.dart';
import '../providers/currency_provider.dart';
import '../database/database_helper.dart';
import 'category_search_field.dart';
import 'item_search_field.dart'; // Import the new item search field
import 'add_category_dialog.dart';
import '../category_management_page.dart';

class AddItemDialog extends StatefulWidget {
  final Item? item;

  const AddItemDialog({super.key, this.item});

  @override
  State<AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<AddItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  Item? _selectedItem;
  final _quantityController = TextEditingController();
  final _unitPriceController = TextEditingController();
  final _totalPriceController = TextEditingController();
  final _quantityFocusNode = FocusNode();
  final _unitPriceFocusNode = FocusNode();
  final _totalPriceFocusNode = FocusNode();
  Category? _selectedCategory;
  String? _selectedImagePath;
  bool _isReadOnly = false;
  bool _isUpdating = false; // Flag to prevent cyclic updates
  bool _fixedQuantityMode = true; // true = quantity is fixed, false = unit price is fixed
  final List<String> _units = ['Kg', 'Liter', 'Pair', 'Hali', 'Piece', 'Packet', 'Meter', 'Bottle', 'Dozen', 'Case', 'Bundle'];
  String _selectedUnit = 'Kg';

  @override
  void initState() {
    super.initState();
    if (widget.item != null) {
      _selectedItem = widget.item;
      _nameController.text = widget.item!.name;
      _unitPriceController.text = widget.item!.price.toString();
      _selectedImagePath = widget.item!.imagePath;
      _isReadOnly = true;
      _fixedQuantityMode = false; // Default to Fixed Price mode when an item is passed

      // Fetch category details from the database using categoryId
      DatabaseHelper().getCategoryById(widget.item!.categoryId).then((category) {
        if (category != null && mounted) {
          setState(() {
            _selectedCategory = category;
          });
        }
      });
    }
    _quantityController.text = '1';
    _updateTotalPrice();
    _quantityController.addListener(_smartCalculate);
    _unitPriceController.addListener(_smartCalculate);
    _totalPriceController.addListener(_smartCalculate);
  }

  void _updateTotalPrice() {
    // Initial calculation for Fixed Price mode
    final quantity = double.tryParse(_quantityController.text);
    final unitPrice = double.tryParse(_unitPriceController.text);
    if (quantity != null && unitPrice != null) {
      _totalPriceController.text = (quantity * unitPrice).toStringAsFixed(2);
    }
  }

  void _smartCalculate() {
    if (_isUpdating) return;
    _isUpdating = true;

    if (_fixedQuantityMode) {
      // Mode: "Fixed Qty". Quantity is the calculated field.
      if (_unitPriceFocusNode.hasFocus || _totalPriceFocusNode.hasFocus) {
        final unitPrice = double.tryParse(_unitPriceController.text);
        final total = double.tryParse(_totalPriceController.text);
        if (total != null && unitPrice != null && unitPrice > 0) {
          final newQuantity = total / unitPrice;
          if (_quantityController.text != newQuantity.toStringAsFixed(3)) {
            _quantityController.text = newQuantity.toStringAsFixed(3);
          }
        } else {
          _quantityController.clear();
        }
      }
    } else {
      // Mode: "Fixed Price". Total Price is the calculated field.
      if (_quantityFocusNode.hasFocus || _unitPriceFocusNode.hasFocus) {
        final quantity = double.tryParse(_quantityController.text);
        final unitPrice = double.tryParse(_unitPriceController.text);
        if (quantity != null && unitPrice != null) {
          final newTotal = quantity * unitPrice;
          if (_totalPriceController.text != newTotal.toStringAsFixed(2)) {
            _totalPriceController.text = newTotal.toStringAsFixed(2);
          }
        } else {
          _totalPriceController.clear();
        }
      }
    }

    _isUpdating = false;
  }

  void _onItemChanged(Item? item) {
    if (item != null) {
      setState(() {
        _selectedItem = item;
        _nameController.text = item.name;
        _unitPriceController.text = item.price.toString();
        _selectedImagePath = item.imagePath;
        _isReadOnly = true;
        _fixedQuantityMode = false; // Switch to Fixed Price mode

        // Reset quantity to 1 and update total price
        _quantityController.text = '1';
        _updateTotalPrice();

        // If the item has a categoryId, fetch its details
        if (item.categoryId != null) {
          DatabaseHelper().getCategoryById(item.categoryId).then((category) {
            if (category != null && mounted) {
              setState(() {
                _selectedCategory = category;
              });
            }
          });
        }
      });
    } else {
      setState(() {
        _selectedItem = null;
        _nameController.clear();
        _unitPriceController.clear();
        _totalPriceController.clear();
        _selectedImagePath = null;
        _isReadOnly = false;
        _selectedCategory = null; // Also clear the category
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _unitPriceController.dispose();
    _totalPriceController.dispose();
    _quantityFocusNode.dispose();
    _unitPriceFocusNode.dispose();
    _totalPriceFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add New Item'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                      value: false,
                      label: Text('Fixed Price', style: TextStyle(fontSize: 12)),
                      icon: Icon(Icons.price_change_outlined)),
                  ButtonSegment<bool>(
                      value: true,
                      label: Text('Fixed Qty', style: TextStyle(fontSize: 12)),
                      icon: Icon(Icons.shopping_bag_outlined)),
                ],
                selected: {_fixedQuantityMode},
                onSelectionChanged: (newSelection) {
                  setState(() {
                    _fixedQuantityMode = newSelection.first;
                  });
                },
              ),
              const SizedBox(height: 16),
              // Conditionally show Item Name and Category fields
              if (widget.item == null) ...[
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Item Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter an item name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                CategorySearchField(
                  onCategorySelected: (category) {
                    setState(() {
                      _selectedCategory = category;
                    });
                  },
                ),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 16),
              TextFormField(
                focusNode: _quantityFocusNode,
                controller: _quantityController,
                readOnly: _fixedQuantityMode, // Read-only in Fixed Qty mode
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                ],
                decoration: InputDecoration(
                  labelText: 'Quantity',
                  border: const OutlineInputBorder(),
                  enabledBorder: _fixedQuantityMode
                      ? const OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.red, width: 1.5),
                        )
                      : null,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Required';
                  }
                  final number = double.tryParse(value);
                  if (number == null || number <= 0) {
                    return 'Invalid';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 32,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Wrap(
                    spacing: 2,
                    runSpacing: 0,
                    children: _units.map((unit) => ChoiceChip(
                      label: Text(unit, style: const TextStyle(fontSize: 10)),
                      selected: _selectedUnit == unit,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _selectedUnit = unit;
                          });
                        }
                      },
                      labelStyle: TextStyle(
                        color: _selectedUnit == unit ? Colors.white : Colors.black87,
                        fontSize: 10,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      selectedColor: Theme.of(context).colorScheme.primary,
                      backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                    )).toList(),
                  ),
                ),
              ),

              const SizedBox(height: 16),
              TextFormField(
                focusNode: _unitPriceFocusNode,
                controller: _unitPriceController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                ],
                decoration: InputDecoration(
                  labelText: 'Unit Price',
                  border: const OutlineInputBorder(),
                  prefixText: '${Provider.of<CurrencyProvider>(context).selectedCurrency.symbol} ',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Required';
                  }
                  final number = double.tryParse(value);
                  if (number == null || number <= 0) {
                    return 'Invalid';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                focusNode: _totalPriceFocusNode,
                controller: _totalPriceController,
                readOnly: !_fixedQuantityMode, // Read-only in Fixed Price mode
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                ],
                decoration: InputDecoration(
                  labelText: 'Total Price',
                  border: const OutlineInputBorder(),
                  prefixText: '${Provider.of<CurrencyProvider>(context).selectedCurrency.symbol} ',
                  enabledBorder: !_fixedQuantityMode
                      ? const OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.red, width: 1.5),
                        )
                      : null,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Required';
                  }
                  final number = double.tryParse(value);
                  if (number == null || number <= 0) {
                    return 'Invalid';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            if (_formKey.currentState!.validate()) {
              // Manual validation for category when adding a new item
              if (widget.item == null && _selectedCategory == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please select a category')),
                );
                return; // Stop execution if category is not selected
              }

              // If an existing item is being edited, its details are already in the state.
              // If a new item is being created, we use the values from the controllers.
              final itemName = _nameController.text;
              final quantity = double.tryParse(_quantityController.text) ?? 1.0;
              final unitPrice = double.tryParse(_unitPriceController.text) ?? 0.0;

              // Use existing item's details if available, otherwise create new ones.
              final itemToSave = widget.item ?? _selectedItem;

              if (itemToSave != null) {
                // This is an existing item, just update price if changed
                if (itemToSave.price != unitPrice) {
                  final updatedItem = itemToSave.copyWith(price: unitPrice);
                  await DatabaseHelper().updateItem(updatedItem);
                }
                Navigator.of(context).pop({
                  'name': itemToSave.name,
                  'quantity': quantity,
                  'price': unitPrice, // Send the potentially updated price
                  'unit': _selectedUnit,
                  'category_id': itemToSave.categoryId,
                  'category_name': _selectedCategory?.name ?? 'N/A',
                  'category_color': _selectedCategory?.color.value ?? Colors.grey.value,
                  'imagePath': _selectedImagePath, // Correct key name
                });
              } else {
                // This is a new item
                Navigator.of(context).pop({
                  'name': itemName,
                  'quantity': quantity,
                  'price': unitPrice,
                  'unit': _selectedUnit,
                  'category_id': _selectedCategory!.id,
                  'category_name': _selectedCategory!.name,
                  'category_color': _selectedCategory!.color.value,
                  'imagePath': _selectedImagePath,
                });
              }
            }
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
