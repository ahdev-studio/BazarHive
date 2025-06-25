import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:image/image.dart' as img;
import 'package:extended_image/extended_image.dart';
import 'package:extended_image_library/extended_image_library.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import '../widgets/banner_ad_widget.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({Key? key}) : super(key: key);

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  static Uint8List _enhanceSignature(Uint8List input) {
    // Convert to image package format
    final img.Image? image = img.decodeImage(input);
    if (image == null) return input;

    // Resize to maintain consistent processing
    final img.Image resized = img.copyResize(
      image,
      width: 300,
      height: 80,
      interpolation: img.Interpolation.average
    );

    // Convert to grayscale first
    final img.Image grayscale = img.grayscale(resized);

    // Apply adaptive thresholding
    final img.Image processed = img.Image.from(grayscale);
    const blockSize = 15;
    const c = 5;

    for (var y = 0; y < grayscale.height; y++) {
      for (var x = 0; x < grayscale.width; x++) {
        // Calculate local mean
        var sum = 0;
        var count = 0;
        for (var i = -blockSize ~/ 2; i <= blockSize ~/ 2; i++) {
          for (var j = -blockSize ~/ 2; j <= blockSize ~/ 2; j++) {
            final px = x + i;
            final py = y + j;
            if (px >= 0 && px < grayscale.width && py >= 0 && py < grayscale.height) {
              sum += img.getLuminance(grayscale.getPixel(px, py)).toInt();
              count++;
            }
          }
        }
        final mean = sum / count;
        final pixel = grayscale.getPixel(x, y);
        final value = img.getLuminance(pixel);
        
        // Apply threshold
        if (value < mean - c) {
          processed.setPixel(x, y, img.ColorRgb8(0, 0, 0));
        } else {
          processed.setPixel(x, y, img.ColorRgb8(255, 255, 255));
        }
      }
    }

    // Encode with medium compression for preview
    return Uint8List.fromList(img.encodePng(processed, level: 3));
  }

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  DateTime? _dateOfBirth;
  String? _profileImagePath;
  String? _signatureImagePath;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameController.text = prefs.getString('userName') ?? '';
      _mobileController.text = prefs.getString('userMobile') ?? '';
      _emailController.text = prefs.getString('userEmail') ?? '';
      _addressController.text = prefs.getString('userAddress') ?? '';
      final dobString = prefs.getString('userDob');
      if (dobString != null) {
        _dateOfBirth = DateTime.parse(dobString);
      }
      _profileImagePath = prefs.getString('profileImagePath');
      _signatureImagePath = prefs.getString('signatureImagePath');
    });
  }

  Future<void> _saveUserData() async {
    if (_formKey.currentState!.validate()) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userName', _nameController.text);
      await prefs.setString('userMobile', _mobileController.text);
      await prefs.setString('userEmail', _emailController.text);
      if (_dateOfBirth != null) {
        await prefs.setString('userDob', _dateOfBirth!.toIso8601String());
      }
      await prefs.setString('userAddress', _addressController.text);
      if (_profileImagePath != null) {
        await prefs.setString('profileImagePath', _profileImagePath!);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      setState(() => _isLoading = true);
      
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: source);
      
      if (image == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Create editor key
      final editorKey = GlobalKey<ExtendedImageEditorState>();
      
      // Show cropping interface
      final Uint8List? croppedImageData = await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              title: const Text('Crop Profile Picture', style: TextStyle(color: Colors.white)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.check, color: Colors.white, size: 28),
                  tooltip: 'Done',
                  onPressed: () async {
                    print('Done button pressed');
                    final state = editorKey.currentState;
                    print('Editor state: $state');
                    
                    if (state != null) {
                      try {
                        // Get raw image data
                        final Uint8List? imageData = state.rawImageData;
                        if (imageData == null) {
                          print('No image data available');
                          return;
                        }
                        
                        // Get crop rect
                        final Rect cropRect = state.getCropRect()!;
                        print('Crop rect: $cropRect');
                        
                        // Load the image for processing
                        final ui.Codec codec = await ui.instantiateImageCodec(imageData);
                        final ui.FrameInfo frameInfo = await codec.getNextFrame();
                        final ui.Image originalImage = frameInfo.image;

                        // Create a picture recorder
                        final ui.PictureRecorder recorder = ui.PictureRecorder();
                        final Canvas canvas = Canvas(recorder);

                        // Calculate scale to maintain aspect ratio
                        final double scaleX = originalImage.width / cropRect.width;
                        final double scaleY = originalImage.height / cropRect.height;
                        final double scale = scaleX < scaleY ? scaleX : scaleY;

                        // Center the image
                        canvas.translate(-cropRect.left * scale, -cropRect.top * scale);
                        canvas.scale(scale);

                        // Draw only the cropped portion
                        canvas.drawImage(originalImage, Offset.zero, Paint());

                        // Convert to image with original dimensions
                        final ui.Image croppedImage = await recorder.endRecording().toImage(
                          cropRect.width.toInt(),
                          cropRect.height.toInt(),
                        );

                        // Convert to bytes
                        final ByteData? byteData = await croppedImage.toByteData(
                          format: ui.ImageByteFormat.png,
                        );
                        
                        if (byteData == null) {
                          print('Failed to get byte data');
                          return;
                        }

                        final Uint8List croppedData = byteData.buffer.asUint8List();

                        // Create a temporary file for compression
                        final tempDir = await getTemporaryDirectory();
                        final tempFile = File('${tempDir.path}/temp_profile.png');
                        await tempFile.writeAsBytes(croppedData);

                        // Final compression to optimize file size
                        final Uint8List? compressedData = await FlutterImageCompress.compressWithFile(
                          tempFile.path,
                          quality: 90,
                        );
                        
                        if (compressedData == null) {
                          print('Failed to compress image');
                          return;
                        }
                        
                        print('Compressed image size: ${compressedData.length} bytes');
                        Navigator.of(context).pop(compressedData);
                      } catch (e) {
                        print('Error during cropping: $e');
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $e'))
                        );
                      }
                    } else {
                      print('Could not find editor state');
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Failed to crop image. Please try again.'))
                      );
                    }
                  },
                ),
              ],
            ),
            body: ExtendedImage.file(
              File(image.path),
              fit: BoxFit.contain,
              mode: ExtendedImageMode.editor,
              extendedImageEditorKey: editorKey,
              cacheRawData: true,
              initEditorConfigHandler: (state) {
                return EditorConfig(
                  maxScale: 8.0,
                  cropRectPadding: const EdgeInsets.all(20.0),
                  hitTestSize: 20.0,
                  cropAspectRatio: 1.0, // 1:1 square ratio
                );
              },
            ),
          ),
        ),
      );

      if (croppedImageData != null) {
        // Save the cropped image
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/profile_${DateTime.now().millisecondsSinceEpoch}.png');
        await tempFile.writeAsBytes(croppedImageData);
        
        setState(() {
          _profileImagePath = tempFile.path;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error picking image: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'))
        );
      }
    }
  }

  void _showImageSourceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Image Source'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        title: const Text('Edit Profile', style: TextStyle(color: Colors.white)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              GestureDetector(
                onTap: _showImageSourceDialog,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.grey[200],
                      backgroundImage: _profileImagePath != null
                          ? FileImage(File(_profileImagePath!))
                          : const AssetImage('assets/images/app_logo.png') as ImageProvider,
                    ),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _mobileController,
                decoration: const InputDecoration(
                  labelText: 'Mobile Number',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _dateOfBirth ?? DateTime.now(),
                    firstDate: DateTime(1900),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setState(() {
                      _dateOfBirth = picked;
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, color: Colors.grey),
                      const SizedBox(width: 12),
                      Text(
                        _dateOfBirth != null
                            ? DateFormat('dd MMM yyyy').format(_dateOfBirth!)
                            : 'Date of Birth',
                        style: TextStyle(
                          color: _dateOfBirth != null ? Colors.black : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_on),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 24),
              // Signature Section
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                'Signature',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                height: 80,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _signatureImagePath != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(_signatureImagePath!),
                          fit: BoxFit.contain,
                        ),
                      )
                    : const Center(
                        child: Text(
                          'No signature added',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _handleSignatureUpload,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.draw),
                label: Text(_signatureImagePath == null
                    ? 'Add Signature'
                    : 'Update Signature'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _saveUserData,
                icon: const Icon(Icons.save),
                label: const Text('Save Profile'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
              ),
              const SizedBox(height: 16),
              const BannerAdWidget(),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Future<void> _handleSignatureUpload() async {
    try {
      setState(() => _isLoading = true);

      // Show bottom sheet for image source selection
      final ImageSource? source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (BuildContext context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take Photo'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );

      if (source == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Pick image
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: source);

      if (image == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Create editor key
      final editorKey = GlobalKey<ExtendedImageEditorState>();
      
      // Show cropping interface
      final Uint8List? croppedImageData = await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              title: const Text('Crop Signature', style: TextStyle(color: Colors.white)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.check, color: Colors.white, size: 28),
                  tooltip: 'Done',
                  onPressed: () async {
                    print('Done button pressed');
                    final state = editorKey.currentState;
                    print('Editor state: $state');
                    
                    if (state != null) {
                      try {
                        // Get raw image data
                        final Uint8List? imageData = state.rawImageData;
                        if (imageData == null) {
                          print('No image data available');
                          return;
                        }
                        
                        // Get crop rect
                        final Rect cropRect = state.getCropRect()!;
                        print('Crop rect: $cropRect');
                        
                        // Load the image for processing
                        final ui.Codec codec = await ui.instantiateImageCodec(imageData);
                        final ui.FrameInfo frameInfo = await codec.getNextFrame();
                        final ui.Image originalImage = frameInfo.image;

                        // Create a picture recorder
                        final ui.PictureRecorder recorder = ui.PictureRecorder();
                        final Canvas canvas = Canvas(recorder);

                        // Calculate scale to fit 300x80
                        final double scaleX = 300 / cropRect.width;
                        final double scaleY = 80 / cropRect.height;
                        final double scale = scaleX < scaleY ? scaleX : scaleY;

                        // Center the image
                        canvas.translate(-cropRect.left * scale, -cropRect.top * scale);
                        canvas.scale(scale);

                        // Draw only the cropped portion
                        canvas.drawImage(originalImage, Offset.zero, Paint());

                        // Convert to image
                        final ui.Image croppedImage = await recorder.endRecording().toImage(
                          300,
                          80,
                        );

                        // Convert to bytes
                        final ByteData? byteData = await croppedImage.toByteData(
                          format: ui.ImageByteFormat.png,
                        );
                        
                        if (byteData == null) {
                          print('Failed to get byte data');
                          return;
                        }

                        final Uint8List croppedData = byteData.buffer.asUint8List();

                        // Create a temporary file for compression
                        final tempDir = await getTemporaryDirectory();
                        final tempFile = File('${tempDir.path}/temp_cropped.png');
                        await tempFile.writeAsBytes(croppedData);

                        // Final compression to optimize file size
                        final Uint8List? compressedData = await FlutterImageCompress.compressWithFile(
                          tempFile.path,
                          minWidth: 300,
                          minHeight: 80,
                          quality: 90,
                        );
                        
                        if (compressedData == null) {
                          print('Failed to compress image');
                          return;
                        }
                        
                        print('Compressed image size: ${compressedData.length} bytes');
                        
                        // Show preview and cleaning option
                        final cleanedImage = await showDialog<Uint8List>(
                          context: context,
                          barrierDismissible: false,
                          builder: (context) => StatefulBuilder(
                            builder: (context, setDialogState) {
                              Uint8List dialogImage = compressedData;
                              bool isProcessing = false;
                              
                              Future<void> enhanceImage() async {
                                if (isProcessing) return; // Prevent multiple processing
                                // Convert to image package format
                                final img.Image? image = img.decodeImage(compressedData);
                                if (image == null) return;
                                
                                // Convert to grayscale
                                final img.Image grayscale = img.grayscale(image);
                                
                                // Increase contrast
                                final img.Image contrast = img.adjustColor(
                                  grayscale,
                                  contrast: 1.3,
                                  brightness: 0.1,
                                );
                                
                                // Remove background (whiten light pixels)
                                for (var i = 0; i < contrast.width; i++) {
                                  for (var j = 0; j < contrast.height; j++) {
                                    final pixel = contrast.getPixel(i, j);
                                    final brightness = img.getLuminance(pixel);
                                    if (brightness > 170) { // Slightly lower threshold
                                      contrast.setPixel(i, j, img.ColorRgb8(255, 255, 255));
                                    }
                                  }
                                }
                                
                                // Final adjustments
                                final img.Image enhanced = img.adjustColor(
                                  contrast,
                                  contrast: 1.2,
                                  brightness: 0.0,
                                  exposure: 0.1, // Slightly increase exposure
                                );
                                
                                return;
                              }
                              
                              return AlertDialog(
                                title: const Text('Signature Preview'),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 300,
                                      height: 80,
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.grey),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: isProcessing
                                        ? const Center(
                                            child: CircularProgressIndicator(),
                                          )
                                        : Image.memory(
                                            dialogImage,
                                            fit: BoxFit.contain,
                                          ),
                                    ),
                                    const SizedBox(height: 16),
                                    ElevatedButton.icon(
                                      onPressed: () async {
                                        print('Clean Signature button pressed');
                                        // Show loading indicator
                                        setDialogState(() {
                                          isProcessing = true;
                                          print('Started processing');
                                        });
                                        
                                        try {
                                          print('Starting image processing');
                                          
                                          final enhancedData = await compute(
                                            _enhanceSignature,

                                            compressedData,
                                          );
                                          
                                          print('Generated enhanced data: ${enhancedData.length} bytes');
                                          // Update the preview
                                          setDialogState(() {
                                            dialogImage = enhancedData;
                                            isProcessing = false;
                                            print('Updated preview with enhanced image');
                                          });
                                        } catch (e) {
                                          print('Error enhancing image: $e');
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Failed to enhance signature')),
                                          );
                                          setDialogState(() {
                                            dialogImage = compressedData; // Restore original on error
                                            isProcessing = false;
                                          });
                                        }
                                      },
                                      icon: const Icon(Icons.auto_fix_high),
                                      label: const Text('Clean Signature'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Theme.of(context).colorScheme.secondary,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                      ),
                                    ),
                                  ],
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () {
                                      Navigator.of(context).pop(compressedData);
                                    },
                                    child: const Text('Use Original'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.of(context).pop(dialogImage),
                                    child: const Text('Done'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Theme.of(context).colorScheme.primary,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        );
                        
                        Navigator.of(context).pop(cleanedImage ?? compressedData);
                      } catch (e) {
                        print('Error during cropping: $e');
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $e'))
                        );
                      }
                    } else {
                      print('Could not find editor state');
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Failed to crop image. Please try again.'))
                      );
                    }
                  },
                ),
              ],
            ),
            body: ExtendedImage.file(
              File(image.path),
              fit: BoxFit.contain,
              mode: ExtendedImageMode.editor,
              extendedImageEditorKey: editorKey,
              cacheRawData: true,
              initEditorConfigHandler: (state) {
                return EditorConfig(
                  maxScale: 8.0,
                  cropRectPadding: const EdgeInsets.all(20.0),
                  hitTestSize: 20.0,
                  cropAspectRatio: 300 / 80, // Fixed aspect ratio for signature
                );
              },
            ),
          ),
        ),
      );

      if (croppedImageData == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Get temporary directory for processing
      final tempDir = await getTemporaryDirectory();
      final tempPath = tempDir.path;
      final outputFileName = 'signature_${DateTime.now().millisecondsSinceEpoch}.png';
      final outputPath = '$tempPath/$outputFileName';

      // Resize the cropped image to 300x80
      final compressedBytes = await FlutterImageCompress.compressWithList(
        croppedImageData,
        minHeight: 80,
        minWidth: 300,
        quality: 90,
        format: CompressFormat.png,
      );

      // Save the final image
      final File outputFile = File(outputPath);
      await outputFile.writeAsBytes(compressedBytes);

      // Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('signatureImagePath', outputPath);

      if (mounted) {
        setState(() {
          _signatureImagePath = outputPath;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signature updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    super.dispose();
  }
}
