import 'dart:io';
import 'package:flutter/material.dart';
import '../models/category.dart';
import '../database/database_helper.dart';
import 'add_category_dialog.dart';
import '../category_management_page.dart';

class CategorySearchField extends StatefulWidget {
  final void Function(Category?) onCategorySelected;
  final Category? initialCategory;

  const CategorySearchField({
    Key? key,
    required this.onCategorySelected,
    this.initialCategory,
  }) : super(key: key);

  @override
  State<CategorySearchField> createState() => _CategorySearchFieldState();
}

class _CategorySearchFieldState extends State<CategorySearchField> {
  final TextEditingController _textEditingController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _autocompleteKey = GlobalKey();

  @override
  void didUpdateWidget(CategorySearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialCategory != oldWidget.initialCategory) {
      // Update the text field if the initial category changes
      _textEditingController.text = widget.initialCategory?.name ?? '';
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialCategory != null) {
      _textEditingController.text = widget.initialCategory!.name;
    }
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        // Trigger options view when the field gains focus
        // This is a bit of a hack to show all options initially
        RawAutocomplete.onFieldSubmitted(_autocompleteKey);
      }
    });
  }

  @override
  void dispose() {
    _textEditingController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _handleAddNewCategory(BuildContext optionsViewContext) async {
    // Unfocus to hide the autocomplete options before showing the dialog
    _focusNode.unfocus();

    // The dialog now handles database updates and notifies all listeners.
    // We just need to show it. The UI will update automatically via notifiers.
    await showAddCategoryDialog(context);
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<Category>(
      key: _autocompleteKey,
      textEditingController: _textEditingController,
      focusNode: _focusNode,
      displayStringForOption: (Category option) => option.name,
      optionsBuilder: (TextEditingValue textEditingValue) async {
        final dbHelper = DatabaseHelper();
        final allCategories = await dbHelper.getCategories();
        if (textEditingValue.text.isEmpty) {
          return allCategories;
        }
        return allCategories.where((Category category) {
          return category.name.toLowerCase().contains(textEditingValue.text.toLowerCase());
        });
      },
      onSelected: (Category selection) {
        widget.onCategorySelected(selection);
      },
      fieldViewBuilder: (BuildContext context, TextEditingController fieldTextEditingController, FocusNode fieldFocusNode, VoidCallback onFieldSubmitted) {
        return TextFormField(
          controller: fieldTextEditingController,
          focusNode: fieldFocusNode,
          decoration: const InputDecoration(
            labelText: 'Category',
            border: OutlineInputBorder(),
            suffixIcon: Icon(Icons.search),
          ),
          onTap: () {
             // When the user taps, we want to show all categories if the field is empty
            if (fieldTextEditingController.text.isEmpty) {
              setState(() {
                 RawAutocomplete.onFieldSubmitted(_autocompleteKey);
              });
            }
          },
        );
      },
      optionsViewBuilder: (BuildContext context, AutocompleteOnSelected<Category> onSelected, Iterable<Category> options) {
        final RenderBox fieldRenderBox = _autocompleteKey.currentContext!.findRenderObject() as RenderBox;
        final double fieldWidth = fieldRenderBox.size.width;

        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4.0,
            child: SizedBox(
              width: fieldWidth,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 250), // Limit height
                child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length + 1, // +1 for "Add New Category"
                itemBuilder: (BuildContext context, int index) {
                  if (index == 0) {
                    // "Add New Category" button
                    return ListTile(
                      leading: const Icon(Icons.add_circle_outline),
                      title: const Text('Add New Category'),
                      onTap: () => _handleAddNewCategory(context),
                    );
                  }
                  final Category option = options.elementAt(index - 1);
                  return ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: option.imagePath == null ? option.color : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: option.imagePath != null
                          ? ClipOval(
                              child: Container(
                                color: Colors.white, // White background for transparent PNGs
                                child: Image.file(
                                  File(option.imagePath!),
                                  fit: BoxFit.cover,
                                  width: 40,
                                  height: 40,
                                  errorBuilder: (context, error, stackTrace) => CircleAvatar(
                                    backgroundColor: option.color,
                                    radius: 20,
                                    child: const Icon(Icons.error, color: Colors.white, size: 20),
                                  ),
                                ),
                              ),
                            )
                          : null,
                    ),
                    title: Text(option.name),
                    onTap: () {
                      onSelected(option);
                    },
                  );
                },
              ),
            ),
          ),
        ));
      },
    );
  }
}
