import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:extended_image/extended_image.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import '../models/category.dart';
import '../database/database_helper.dart';
import 'package:sqflite/sqflite.dart';
import '../category_management_page.dart';
import '../services/category_notifier.dart';

/// Shows a dialog to add or edit a category.
///
/// For adding, call without `categoryToEdit`.
/// For editing, pass the `categoryToEdit`.
/// Returns `true` if the operation was successful, otherwise `false` or `null`.
Future<bool?> showAddCategoryDialog(BuildContext context, {Category? categoryToEdit}) async {
  final isEditing = categoryToEdit != null;
  final TextEditingController nameController =
      TextEditingController(text: categoryToEdit?.name);
  String? nameErrorText;
  String? colorErrorText;

  Color? selectedColor = isEditing ? categoryToEdit!.color : null;
  File? _image;

  if (categoryToEdit?.imagePath != null && categoryToEdit!.imagePath!.isNotEmpty) {
    _image = File(categoryToEdit.imagePath!);
  }

  return showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setState) {
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
                              onPressed: _isLoading ? null : () async {
                                setState(() { _isLoading = true; });
                                try {
                                  final state = editorKey.currentState;
                                  if (state == null) {
                                    setState(() { _isLoading = false; });
                                    return;
                                  }

                                  final Rect? cropRect = state.getCropRect();
                                  final Uint8List rawData = state.rawImageData;

                                  if (cropRect == null) {
                                    Navigator.pop<String>(context);
                                    return;
                                  }

                                  final img.Image? originalImage = img.decodeImage(rawData);
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

                                  // Create a new image with a white background for PNG transparency
                                  final img.Image finalImage = img.Image(
                                    width: croppedImage.width,
                                    height: croppedImage.height,
                                  );
                                  img.fill(finalImage, color: img.ColorRgb8(255, 255, 255));
                                  img.compositeImage(finalImage, croppedImage);

                                  final Uint8List croppedBytes = Uint8List.fromList(img.encodePng(finalImage));

                                  final Uint8List compressedBytes = await FlutterImageCompress.compressWithList(
                                    croppedBytes,
                                    minHeight: 512,
                                    minWidth: 512,
                                    quality: 85,
                                  );

                                  final tempDir = await getTemporaryDirectory();
                                  final String targetPath = '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.png';
                                  final File newFile = File(targetPath);
                                  await newFile.writeAsBytes(compressedBytes);

                                  Navigator.pop<String>(context, newFile.path);
                                } catch (e) {
                                  debugPrint("Error cropping/saving image: $e");
                                  if (context.mounted) {
                                    setState(() { _isLoading = false; });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Failed to process image. Please try again.')),
                                    );
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
                                  cropAspectRatio: 1.0, // 1:1 aspect ratio
                                  hitTestSize: 20.0,
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
                _image = File(croppedFilePath);
              });
            }
          }


          return AlertDialog(
            title: Text(isEditing ? 'Edit Category' : 'Add New Category'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Image Picker as CircleAvatar
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
                                    }
                                  )
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.grey[200],
                      backgroundImage: _image != null ? FileImage(_image!) : null,
                      child: _image == null
                          ? const Icon(
                              Icons.add_a_photo,
                              color: Colors.grey,
                              size: 40,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Category Name Input
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: 'Category Name',
                      hintText: 'Enter category name',
                      errorText: nameErrorText,
                      border: const OutlineInputBorder(),
                    ),
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 16),
                  
                  // Color Selection Label
                  Row(
                    children: [
                      const Text(
                        'Select Color:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (colorErrorText != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            colorErrorText!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  


                  // Color Selection Grid
                  SizedBox(
                    height: 50,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: CategoryManagementPage.presetColors.length,
                      itemBuilder: (context, index) {
                        final color = CategoryManagementPage.presetColors[index];
                        final isSelected = selectedColor != null && color.value == selectedColor?.value;
                        
                        return GestureDetector(
                          onTap: () {
                            final oldColor = selectedColor?.value.toRadixString(16).toUpperCase();
                            setState(() {
                              selectedColor = color;
                              debugPrint('Changed color from: ${oldColor != null ? "0x$oldColor" : "none"} to: 0x${color.value.toRadixString(16).toUpperCase()}');
                            });
                          },
                          child: Container(
                            width: 40,
                            height: 40,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? Colors.white : Colors.transparent,
                                width: 3,
                              ),
                              boxShadow: [
                                if (isSelected)
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  
                  // Validate input
                  bool hasError = false;
                  
                  if (name.isEmpty) {
                    setState(() {
                      nameErrorText = 'Please enter a category name';
                    });
                    hasError = true;
                  } else {
                    setState(() {
                      nameErrorText = null;
                    });
                  }

                  if (selectedColor == null) {
                    setState(() {
                      colorErrorText = 'Please select a color';
                    });
                    hasError = true;
                  } else {
                    setState(() {
                      colorErrorText = null;
                    });
                  }

                  if (hasError) return;

                  // At this point selectedColor is not null because we validated it above
                  final colorValue = selectedColor!.value;
                  try {
                    final dbHelper = DatabaseHelper();
                    final name = nameController.text.trim();
                    final color = selectedColor!.value;
                    final imagePath = _image?.path;

                    if (isEditing) {
                      await dbHelper.updateCategory(
                        categoryToEdit!.id!,
                        name,
                        color,
                        imagePath: imagePath,
                      );
                    } else {
                      await dbHelper.insertCategory(
                        name,
                        color,
                        imagePath: imagePath,
                      );
                    }

                    // Notify all listeners that the categories have changed.
                    CategoryNotifier.instance.notify();

                    if (context.mounted) {
                      Navigator.of(context).pop(true); // Success
                    }
                  } catch (e) {
                    debugPrint('Failed to save category: $e');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: ${e.toString()}')),
                      );
                      Navigator.of(context).pop(false); // Failure
                    }
                  }
                },
                child: Text(isEditing ? 'Save' : 'Add'),
              ),
            ],
          );
        },
      );
    },
  );
}
