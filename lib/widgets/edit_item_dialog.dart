import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/shopping_item.dart';
import '../models/category.dart';
import '../category_management_page.dart';
import '../providers/currency_provider.dart';
import 'category_search_field.dart';

class EditItemDialog extends StatefulWidget {
  final ShoppingItem item;
  final Map<String, Category> categories;

  const EditItemDialog({
    super.key,
    required this.item,
    required this.categories,
  });

  @override
  State<EditItemDialog> createState() => _EditItemDialogState();
}

class _EditItemDialogState extends State<EditItemDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController quantityController;
  late TextEditingController unitPriceController;
  late TextEditingController totalPriceController;
  final _quantityFocusNode = FocusNode();
  final _unitPriceFocusNode = FocusNode();
  final _totalPriceFocusNode = FocusNode();
  late DateTime? doneTime;
  late String selectedCategory;
  late int? selectedCategoryId;
  late int selectedCategoryColor;
  bool _isUpdating = false;
  bool _fixedQuantityMode = true;
  final List<String> units = ['Kg', 'Liter', 'Pair', 'Hali', 'Piece', 'Packet', 'Meter', 'Bottle', 'Dozen', 'Case', 'Bundle'];
  late String selectedUnit;

  @override
  void initState() {
    super.initState();
    quantityController = TextEditingController(text: widget.item.quantity.toString());
    unitPriceController = TextEditingController(text: widget.item.unitPrice.toString());
    totalPriceController = TextEditingController(text: (widget.item.quantity * widget.item.unitPrice).toStringAsFixed(2));
    doneTime = widget.item.doneTime;
    selectedCategory = widget.item.category;
    selectedCategoryId = widget.item.categoryId;
    selectedCategoryColor = widget.item.categoryColor;
    selectedUnit = widget.item.unit;

    // Default to Fixed Price mode, which is more intuitive for editing.
    _fixedQuantityMode = false;

    quantityController.addListener(_smartCalculate);
    unitPriceController.addListener(_smartCalculate);
    totalPriceController.addListener(_smartCalculate);
  }

  void _smartCalculate() {
    if (_isUpdating) return;
    _isUpdating = true;

    if (_fixedQuantityMode) {
      // Mode: "Fixed Qty". Quantity is calculated from Unit Price and Total Price.
      if (_unitPriceFocusNode.hasFocus || _totalPriceFocusNode.hasFocus) {
        final unitPrice = double.tryParse(unitPriceController.text);
        final total = double.tryParse(totalPriceController.text);
        if (total != null && unitPrice != null && unitPrice > 0) {
          final newQuantity = total / unitPrice;
          if (quantityController.text != newQuantity.toStringAsFixed(3)) {
            quantityController.text = newQuantity.toStringAsFixed(3);
          }
        } else {
          // Do not clear if one of the fields is empty, wait for user input
        }
      }
    } else {
      // Mode: "Fixed Price". Total Price is calculated from Quantity and Unit Price.
      if (_quantityFocusNode.hasFocus || _unitPriceFocusNode.hasFocus) {
        final quantity = double.tryParse(quantityController.text);
        final unitPrice = double.tryParse(unitPriceController.text);
        if (quantity != null && unitPrice != null) {
          final newTotal = quantity * unitPrice;
          if (totalPriceController.text != newTotal.toStringAsFixed(2)) {
            totalPriceController.text = newTotal.toStringAsFixed(2);
          }
        } else {
          // Do not clear if one of the fields is empty, wait for user input
        }
      }
    }

    _isUpdating = false;
  }

  @override
  void dispose() {
    quantityController.dispose();
    unitPriceController.dispose();
    totalPriceController.dispose();
    _quantityFocusNode.dispose();
    _unitPriceFocusNode.dispose();
    _totalPriceFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currencySymbol = Provider.of<CurrencyProvider>(context).selectedCurrencySymbol;

    return AlertDialog(
      title: const Text('Edit Item'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CategorySearchField(
                initialCategory: widget.item.categoryId != null
                    ? Category(
                        id: widget.item.categoryId!,
                        name: selectedCategory,
                        color: Color(selectedCategoryColor))
                    : null,
                onCategorySelected: (category) {
                  if (category != null) {
                    setState(() {
                      selectedCategory = category.name;
                      selectedCategoryId = category.id;
                      selectedCategoryColor = category.color.value;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
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
              TextFormField(
                focusNode: _quantityFocusNode,
                controller: quantityController,
                readOnly: _fixedQuantityMode,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
                decoration: InputDecoration(
                  labelText: 'Quantity',
                  border: const OutlineInputBorder(),
                  enabledBorder: _fixedQuantityMode
                      ? OutlineInputBorder(
                          borderSide: const BorderSide(color: Colors.red, width: 1.5),
                        )
                      : null,
                ),
                validator: (v) => (v == null || v.isEmpty || double.tryParse(v) == null || double.parse(v) <= 0) ? 'Invalid' : null,
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 32,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Wrap(
                    spacing: 2,
                    children: units.map((unit) => ChoiceChip(
                      label: Text(unit, style: const TextStyle(fontSize: 10)),
                      selected: selectedUnit == unit,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            selectedUnit = unit;
                          });
                        }
                      },
                      labelStyle: TextStyle(
                        color: selectedUnit == unit ? Colors.white : Colors.black87,
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
                controller: unitPriceController,
                readOnly: false, // Always editable
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
                decoration: InputDecoration(labelText: 'Unit Price', border: const OutlineInputBorder(), prefixText: '$currencySymbol '),
                validator: (v) => (v == null || v.isEmpty || double.tryParse(v) == null || double.parse(v) <= 0) ? 'Invalid' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                focusNode: _totalPriceFocusNode,
                controller: totalPriceController,
                readOnly: !_fixedQuantityMode,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
                decoration: InputDecoration(
                  labelText: 'Total Price',
                  border: const OutlineInputBorder(),
                  prefixText: '$currencySymbol ',
                  enabledBorder: !_fixedQuantityMode
                      ? OutlineInputBorder(
                          borderSide: const BorderSide(color: Colors.red, width: 1.5),
                        )
                      : null,
                ),
                validator: (v) => (v == null || v.isEmpty || double.tryParse(v) == null || double.parse(v) <= 0) ? 'Invalid' : null,
              ),
              if (widget.item.doneTime != null) ...[
                const SizedBox(height: 16),
                TextButton.icon(
                  icon: const Icon(Icons.calendar_today),
                  label: const Text('Change Purchase Date/Time'),
                  onPressed: () async {
                    final date = await showDatePicker(context: context, initialDate: doneTime ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2101));
                    if (date == null) return;
                    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(doneTime ?? DateTime.now()));
                    if (time != null) {
                      setState(() {
                        doneTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                      });
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop({
                'quantity': double.parse(quantityController.text),
                'unitPrice': double.parse(unitPriceController.text),
                'unit': selectedUnit,
                'category': selectedCategory,
                'categoryId': selectedCategoryId,
                'categoryColor': selectedCategoryColor,
                'doneTime': doneTime,
                'imagePath': widget.item.imagePath, // Preserve the image path
              });
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
