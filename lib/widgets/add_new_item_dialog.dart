import 'dart:io';

import 'package:BazarHive/widgets/category_dropdown.dart';
import 'package:BazarHive/models/item.dart';
import 'package:BazarHive/database/database_helper.dart';
import 'package:BazarHive/services/category_notifier.dart';
import 'package:BazarHive/services/item_notifier.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'package:extended_image/extended_image.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;

class AddNewItemDialog extends StatefulWidget {
  final Item? itemToEdit;

  const AddNewItemDialog({super.key, this.itemToEdit});

  @override
  State<AddNewItemDialog> createState() => _AddNewItemDialogState();
}

class _AddNewItemDialogState extends State<AddNewItemDialog> {
  final _formKey = GlobalKey<FormState>();
  String? _imagePath;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  int? _selectedCategoryId;
  Key _categoryDropdownKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    if (widget.itemToEdit != null) {
      _nameController.text = widget.itemToEdit!.name;
      _priceController.text = widget.itemToEdit!.price.toString();
      _selectedCategoryId = widget.itemToEdit!.categoryId;
      _imagePath = widget.itemToEdit!.imagePath;
    }
    CategoryNotifier.instance.addListener(_onCategoryUpdated);
  }

  void _onCategoryUpdated() {
    setState(() {
      // By changing the key, we force the CategoryDropdown to rebuild and refetch categories.
      _categoryDropdownKey = UniqueKey();
    });
  }

  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    CategoryNotifier.instance.removeListener(_onCategoryUpdated);
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);

    if (pickedFile == null) return;

    final editorKey = GlobalKey<ExtendedImageEditorState>();
    final File imageFile = File(pickedFile.path);

    // Navigate to crop page
    final String? croppedFilePath = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) {
          bool _isLoading = false;
          return StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return Scaffold(
                backgroundColor: Colors.black,
                appBar: AppBar(
                  backgroundColor: Theme.of(context).primaryColor,
                  title: const Text("Crop & Edit Image"),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.check, color: Colors.white),
                      onPressed: _isLoading
                          ? null
                          : () async {
                              setState(() {
                                _isLoading = true;
                              });
                              try {
                                final state = editorKey.currentState;
                                if (state == null) {
                                  setState(() {
                                    _isLoading = false;
                                  });
                                  return;
                                }

                                final Rect? cropRect = state.getCropRect();
                                final Uint8List rawData = state.rawImageData;

                                if (cropRect == null) {
                                  Navigator.pop<String>(context);
                                  return;
                                }

                                final img.Image? originalImage =
                                    img.decodeImage(rawData);
                                if (originalImage == null) {
                                  Navigator.pop<String>(context);
                                  return;
                                }
                                final img.Image croppedImage = img.copyCrop(
                                  originalImage,
                                  x: cropRect.left.toInt(),
                                  y: cropRect.top.toInt(),
                                  width: cropRect.width.toInt(),
                                  height: cropRect.height.toInt(),
                                );

                                // Get temp directory
                                final tempDir =
                                    await getTemporaryDirectory();
                                final String targetPath =
                                    '${tempDir.path}/cropped_${DateTime.now().millisecondsSinceEpoch}.jpg';

                                // Save the cropped image
                                final File croppedFile = File(targetPath);
                                await croppedFile.writeAsBytes(
                                    img.encodeJpg(croppedImage, quality: 85));

                                Navigator.pop<String>(context, targetPath);
                              } catch (e) {
                                debugPrint('Error cropping image: $e');
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content:
                                          Text('Error cropping image: $e')),
                                );
                              } finally {
                                if (mounted) {
                                  setState(() {
                                    _isLoading = false;
                                  });
                                }
                              }
                            },
                    ),
                  ],
                ),
                body: Stack(
                  children: [
                    ExtendedImage.file(
                      imageFile,
                      cacheRawData: true,
                      fit: BoxFit.contain,
                      mode: ExtendedImageMode.editor,
                      extendedImageEditorKey: editorKey,
                      initEditorConfigHandler: (state) {
                        return EditorConfig(
                          maxScale: 8.0,
                          cropRectPadding: const EdgeInsets.all(20.0),
                          hitTestSize: 20.0,
                          cropAspectRatio: 1.0, // Crop to a square
                        );
                      },
                    ),
                    if (_isLoading)
                      Container(
                        color: Colors.black.withOpacity(0.7),
                        child: const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
                bottomNavigationBar: BottomAppBar(
                  color: Theme.of(context).primaryColor,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: <Widget>[
                      TextButton(
                        onPressed: () => editorKey.currentState?.flip(),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.flip, color: Colors.white),
                            SizedBox(height: 2),
                            Text("Flip", style: TextStyle(color: Colors.white, fontSize: 12)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => editorKey.currentState?.rotate(right: false),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.rotate_left, color: Colors.white),
                            SizedBox(height: 2),
                            Text("Left", style: TextStyle(color: Colors.white, fontSize: 12)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => editorKey.currentState?.rotate(right: true),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.rotate_right, color: Colors.white),
                            SizedBox(height: 2),
                            Text("Right", style: TextStyle(color: Colors.white, fontSize: 12)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => editorKey.currentState?.reset(),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.restore, color: Colors.white),
                            SizedBox(height: 2),
                            Text("Reset", style: TextStyle(color: Colors.white, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );

    if (croppedFilePath != null) {
      setState(() {
        _imagePath = croppedFilePath;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.itemToEdit == null ? 'Add New Item' : 'Edit Item'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              GestureDetector(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        title: const Text('Select Image Source'),
                        content: SingleChildScrollView(
                          child: ListBody(
                            children: <Widget>[
                              GestureDetector(
                                child: const Text('Gallery'),
                                onTap: () {
                                  _pickImage(ImageSource.gallery);
                                  Navigator.of(context).pop();
                                },
                              ),
                              const Padding(padding: EdgeInsets.all(8.0)),
                              GestureDetector(
                                child: const Text('Camera'),
                                onTap: () {
                                  _pickImage(ImageSource.camera);
                                  Navigator.of(context).pop();
                                },
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _imagePath != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(_imagePath!),
                            fit: BoxFit.cover,
                          ),
                        )
                      : const Icon(
                          Icons.add_a_photo,
                          color: Colors.grey,
                          size: 50,
                        ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Item Name', border: OutlineInputBorder()),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter an item name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              CategoryDropdown(
                key: _categoryDropdownKey,
                initialCategoryId: _selectedCategoryId,
                onCategorySelected: (category) {
                  setState(() {
                    _selectedCategoryId = category?.id;
                  });
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _priceController,
                decoration: const InputDecoration(labelText: 'Unit Price', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a price';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Please enter a valid number';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('Cancel'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        ElevatedButton(
          child: const Text('Save'),
          onPressed: () async {
            if (_formKey.currentState!.validate()) {
              if (_selectedCategoryId == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please select a category')),
                );
                return;
              }

              final item = Item(
                id: widget.itemToEdit?.id,
                name: _nameController.text,
                categoryId: _selectedCategoryId!,
                price: double.parse(_priceController.text),
                imagePath: _imagePath,
              );

              final dbHelper = DatabaseHelper();
              if (widget.itemToEdit == null) {
                await dbHelper.insertItem(item);
              } else {
                await dbHelper.updateItem(item);
              }
              // Notify listeners that an item was added or updated
              ItemNotifier.instance.notify();
              Navigator.of(context).pop();
            }
          },
        ),
      ],
    );
  }
}
