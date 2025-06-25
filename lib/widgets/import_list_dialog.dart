import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../models/shopping_item.dart';
import '../providers/currency_provider.dart';

class ImportListDialog extends StatefulWidget {
  final String ownerName;
  final List<Map<String, dynamic>> items;
  final Function(String categoryName, Color color, List<ShoppingItem> items) onImport;

  const ImportListDialog({
    super.key,
    required this.ownerName,
    required this.items,
    required this.onImport,
  });

  @override
  State<ImportListDialog> createState() => _ImportListDialogState();
}

class _ImportListDialogState extends State<ImportListDialog> {
  Color selectedColor = Colors.blue;
  final List<Color> colorOptions = [
    Colors.blue,
    Colors.green,
    Colors.red,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.pink,
    Colors.indigo,
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedColor();
  }

  Future<void> _loadSavedColor() async {
    final prefs = await SharedPreferences.getInstance();
    final savedColor = prefs.getInt('category_color_${widget.ownerName}');
    if (savedColor != null) {
      setState(() {
        selectedColor = Color(savedColor);
      });
    }
  }

  Future<void> _saveColor() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('category_color_${widget.ownerName}', selectedColor.value);
  }

  @override
  Widget build(BuildContext context) {
    final categoryName = "${widget.ownerName}'s list";
    double total = 0;
    
    final items = widget.items.map((item) {
      final quantity = item['quantity'] as num;
      final unitPrice = item['unitPrice'] as num;
      final itemTotal = quantity * unitPrice;
      total += itemTotal;
      
      final itemPrice = quantity * unitPrice;
      return ShoppingItem(
        name: item['itemName'],
        quantity: quantity.toDouble(),
        unit: item['unit'],
        price: itemPrice.toDouble(),
        unitPrice: unitPrice.toDouble(),
        category: categoryName,
        categoryColor: selectedColor.value,
      );
    }).toList();

    return AlertDialog(
      title: Text('Import ${widget.ownerName}\'s List'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Category Color:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: colorOptions.map((color) => GestureDetector(
                onTap: () => setState(() => selectedColor = color),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selectedColor == color ? Colors.black : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
              )).toList(),
            ),
            const SizedBox(height: 16),
            const Text(
              'Items:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final itemTotal = item.quantity * item.unitPrice;
                  return ListTile(
                    dense: true,
                    title: Text(item.name),
                    subtitle: Consumer<CurrencyProvider>(
                      builder: (context, currencyProvider, child) => Text(
                        '${item.quantity} ${item.unit} × ${currencyProvider.selectedCurrency.symbol}${item.unitPrice} = ${currencyProvider.selectedCurrency.symbol}$itemTotal',
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Consumer<CurrencyProvider>(
                  builder: (context, currencyProvider, child) => Text(
                    'Total: ${currencyProvider.selectedCurrency.symbol}$total',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            await _saveColor();
            if (context.mounted) {
              widget.onImport(categoryName, selectedColor, items);
              Navigator.pop(context);
            }
          },
          child: const Text('Import'),
        ),
      ],
    );
  }
}
