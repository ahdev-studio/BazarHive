import 'dart:io';
import 'package:flutter/material.dart';
import '../models/item.dart';
import '../database/database_helper.dart';
import 'add_new_item_dialog.dart';

class ItemSearchField extends StatefulWidget {
  final void Function(Item?) onItemChanged;
  final Item? initialItem;
  final TextEditingController controller;
  final FormFieldValidator<String>? validator;

  const ItemSearchField({
    Key? key,
    required this.onItemChanged,
    this.initialItem,
    required this.controller,
    this.validator,
  }) : super(key: key);

  @override
  State<ItemSearchField> createState() => _ItemSearchFieldState();
}

class _ItemSearchFieldState extends State<ItemSearchField> {
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _autocompleteKey = GlobalKey();
  List<Item> _items = [];

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final dbHelper = DatabaseHelper();
    final items = await dbHelper.getItems();
    if (mounted) {
      setState(() {
        _items = items;
      });
    }
  }

  Future<void> _showAddNewItemDialog() async {
    await showDialog(
      context: context,
      builder: (context) => const AddNewItemDialog(),
    );
    // After dialog closes, reload items to see the new one
    await _loadItems();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<Item>(
      key: _autocompleteKey,
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text == '') {
          // When the field is empty, show all items
          return _items;
        }
        return _items.where((Item option) {
          return option.name.toLowerCase().contains(textEditingValue.text.toLowerCase());
        });
      },
      onSelected: (Item selection) {
        widget.controller.text = selection.name;
        widget.onItemChanged(selection);
      },
      fieldViewBuilder: (BuildContext context, TextEditingController fieldTextEditingController, FocusNode fieldFocusNode, VoidCallback onFieldSubmitted) {
        return TextFormField(
          controller: fieldTextEditingController,
          focusNode: fieldFocusNode,
          decoration: const InputDecoration(
            labelText: 'Item Name',
            border: OutlineInputBorder(),
          ),
          validator: widget.validator,
          onChanged: (value) {
            // When user types, we clear the selected item if it was previously selected
            if (widget.initialItem != null && value != widget.initialItem!.name) {
              widget.onItemChanged(null);
            }
          },
        );
      },
      optionsViewBuilder: (BuildContext context, AutocompleteOnSelected<Item> onSelected, Iterable<Item> options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4.0,
            child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: options.length + 1, // +1 for 'Add New Item'
                itemBuilder: (BuildContext context, int index) {
                  if (index == 0) {
                    return ListTile(
                      leading: const Icon(Icons.add_circle_outline, color: Colors.blue),
                      title: const Text('Add New Item', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                      onTap: () {
                        _showAddNewItemDialog();
                        // Close the options view
                        _focusNode.unfocus();
                      },
                    );
                  }
                  final Item option = options.elementAt(index - 1);
                  return ListTile(
                    leading: option.imagePath != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.file(
                              File(option.imagePath!),
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image),
                            ),
                          )
                        : const Icon(Icons.shopping_cart),
                    title: Text(option.name),
                    subtitle: Text('Price: ${option.price}'),
                    onTap: () {
                      onSelected(option);
                    },
                  );
                },
              ),
            ),
        );
      },
    );
  }
}
