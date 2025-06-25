import 'dart:io';
import 'package:flutter/material.dart';
import '../models/shopping_item.dart';
import '../providers/currency_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:printing/printing.dart';
import '../widgets/banner_ad_widget.dart';
import '../services/ad_helper.dart';

final List<String> _categories = [];

  class BoughtReportPage extends StatefulWidget {
  const BoughtReportPage({super.key});

  @override
  State<BoughtReportPage> createState() => _BoughtReportPageState();
  }

  class _BoughtReportPageState extends State<BoughtReportPage> {
  DateTime? _fromDateTime;
  DateTime? _toDateTime;
  final Set<String> _selectedCategories = {};
  final List<ShoppingItem> _boughtItems = [];
  Map<String, List<ShoppingItem>> _groupedItems = {};
  final DatabaseHelper _databaseHelper = DatabaseHelper();
  bool _isLoading = true;
  bool _isSavingPDF = false;
  
  // Interstitial ad helper
  final InterstitialAdHelper _adHelper = InterstitialAdHelper();

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadBoughtItems();
    
    // Load interstitial ad
    _adHelper.loadAd();
  }

  Future<void> _loadCategories() async {
    final db = await _databaseHelper.database;
    final List<Map<String, dynamic>> maps = await db.query('categories');
    
    setState(() {
      _categories.clear();
      _categories.addAll(maps.map((map) => map['name'] as String));
    });
  }

  Future<void> _loadBoughtItems() async {
    setState(() => _isLoading = true);

    try {
      List<Map<String, dynamic>> items;
      if (_fromDateTime != null && _toDateTime != null) {
        items = await _databaseHelper.getBoughtItemsByDateRange(
          _fromDateTime!,
          _toDateTime!,
        );
      } else {
        items = await _databaseHelper.getBoughtItems();
      }

      final loadedItems = items.map((item) => ShoppingItem(
        id: item['id'] as int,
        name: item['name'] as String,
        quantity: item['quantity'] as double,
        unit: item['unit'] as String,
        price: item['price'] as double,
        category: item['category'] as String,
        categoryColor: item['categoryColor'] as int,
        unitPrice: item['unitPrice'] as double,
        imagePath: item['imagePath'] as String?,
        isBought: true,
        doneTime: DateTime.fromMillisecondsSinceEpoch(item['boughtTime'] as int),
      )).toList();

      setState(() {
        _boughtItems.clear();
        // When no categories are selected, show all items
        if (_selectedCategories.isEmpty) {
          _boughtItems.addAll(loadedItems);
        } else {
          // Only show items from selected categories
          _boughtItems.addAll(
            loadedItems.where((item) => _selectedCategories.contains(item.category))
          );
        }
        // Sort items by date, most recent first
        _boughtItems.sort((a, b) => b.doneTime!.compareTo(a.doneTime!));
        _groupedItems = _groupItemsByCategory(_boughtItems);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading items: $e')),
        );
      }
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

  Future<void> _selectDateTime(bool isFromDate) async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: isFromDate ? (_fromDateTime ?? DateTime.now()) : (_toDateTime ?? DateTime.now()),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );

    if (date == null) return;

    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (time == null) return;

    final DateTime dateTime = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    setState(() {
      if (isFromDate) {
        _fromDateTime = dateTime;
      } else {
        _toDateTime = dateTime;
      }
    });

    _loadBoughtItems();
  }

  double _calculateTotalAmount() {
    return _boughtItems.fold(0, (sum, item) => sum + item.price);
  }

  Future<String> _generateAndSavePDF() async {
    try {
      final currencySymbol = context.read<CurrencyProvider>().selectedCurrencySymbol;
      // Request storage permission
      if (!await Permission.storage.request().isGranted) {
        return 'Storage permission denied';
      }

      // Create PDF document
      final pdf = pw.Document();
      
      // Get currency symbol and convert to ASCII if needed
      String displayCurrency;
      switch (currencySymbol) {
        case '৳':
          displayCurrency = 'Tk. ';
          break;
        case '₹':
          displayCurrency = 'Rs. ';
          break;
        case r'$':
          displayCurrency = r'$ ';
          break;
        case '£':
          displayCurrency = '£ ';
          break;
        case '€':
          displayCurrency = '€ ';
          break;
        case '¥':
          displayCurrency = '¥ ';
          break;
        case '₩':
          displayCurrency = '₩ ';
          break;
        case '₽':
          displayCurrency = 'RUB ';
          break;
        case '﷼':
          displayCurrency = 'SAR ';
          break;
        case '₺':
          displayCurrency = 'TL ';
          break;
        case '₦':
          displayCurrency = 'NGN ';
          break;
        case r'A$':
          displayCurrency = r'A$ ';
          break;
        case r'C$':
          displayCurrency = r'C$ ';
          break;
        case r'R$':
          displayCurrency = r'R$ ';
          break;
        case 'CHF':
          displayCurrency = 'CHF ';
          break;
        case 'AED':
          displayCurrency = 'AED ';
          break;
        case 'ZAR':
          displayCurrency = 'ZAR ';
          break;
        default:
          displayCurrency = '$currencySymbol ';
      }
      // Get user info
      final prefs = await SharedPreferences.getInstance();
      final userName = prefs.getString('userName') ?? 'Unknown User';
      final userMobile = prefs.getString('userMobile') ?? 'N/A';
      final profileImagePath = prefs.getString('profileImagePath');
      final signatureImagePath = prefs.getString('signatureImagePath');
      
      // Load images
      final appLogo = await rootBundle.load('assets/images/app_logo.png');
      final appLogoImage = pw.MemoryImage(appLogo.buffer.asUint8List());
      
      // Load profile image
      pw.ImageProvider? profileImage;
      if (profileImagePath != null) {
        try {
          final file = File(profileImagePath);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            profileImage = pw.MemoryImage(bytes);
          }
        } catch (e) {
          print('Error loading profile image: $e');
        }
      }

      // Load signature image
      pw.ImageProvider? signatureImage;
      if (signatureImagePath != null) {
        try {
          final file = File(signatureImagePath);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            signatureImage = pw.MemoryImage(bytes);
          }
        } catch (e) {
          print('Error loading signature image: $e');
        }
      }

      // Group items by category
      final groupedItems = <String, List<ShoppingItem>>{};
      for (var item in _boughtItems) {
        if (!groupedItems.containsKey(item.category)) {
          groupedItems[item.category] = [];
        }
        groupedItems[item.category]!.add(item);
      }

      // Check if dates are selected
      if (_fromDateTime == null || _toDateTime == null) {
        return 'Please select both From Date and To Date';
      }

      // Format dates for file name
      final fromDate = DateFormat('dd MMM yyyy').format(_fromDateTime!);
      final toDate = DateFormat('dd MMM yyyy').format(_toDateTime!);
      final fileName = '$fromDate to $toDate.pdf';

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (context) => [
            // Header
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Row(
                  children: [
                    pw.Container(
                      width: 50,
                      height: 50,
                      decoration: pw.BoxDecoration(
                        shape: pw.BoxShape.circle,
                        border: pw.Border.all(color: PdfColors.grey800, width: 2),
                      ),
                      child: pw.ClipOval(
                        child: profileImage != null ? pw.Image(profileImage) : pw.Image(appLogoImage),
                      ),
                    ),
                    pw.SizedBox(width: 10),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(userName, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                        pw.Text('Mobile No: $userMobile', style: pw.TextStyle(fontSize: 10)),
                      ],
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('powered by'),
                    pw.Row(
                      children: [
                        pw.Text('BazarHive App '),
                        pw.Container(
                          width: 20,
                          height: 20,
                          child: pw.Image(appLogoImage),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 20),

            // Report Info
            pw.Text('Generated on: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}'),
            pw.Text('Date Range: From ${DateFormat('dd MMM yyyy, hh:mm a').format(_fromDateTime!)} to ${DateFormat('dd MMM yyyy, hh:mm a').format(_toDateTime!)}'),
            pw.Text('Selected Categories: ${_selectedCategories.isEmpty ? 'All Categories' : _selectedCategories.join(', ')}'),
            pw.SizedBox(height: 20),

            // Items by Category
            ...groupedItems.entries.map((entry) {
              final categoryItems = entry.value;
              final subtotal = categoryItems.fold<double>(0, (sum, item) => sum + item.price);

              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Divider(),
                  pw.Text('* ${entry.key}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  pw.Table(
                    border: pw.TableBorder.all(),
                    columnWidths: {
                      0: const pw.FixedColumnWidth(20),   // SL
                      1: const pw.FlexColumnWidth(2),     // Item Name
                      2: const pw.FixedColumnWidth(30),   // Qty
                      3: const pw.FixedColumnWidth(30),   // Unit
                      4: const pw.FlexColumnWidth(1.5),   // Unit Price
                      5: const pw.FlexColumnWidth(1.5),   // Total
                      6: const pw.FixedColumnWidth(60),   // Date & Time
                    },
                    children: [
                      // Table Header
                      pw.TableRow(
                        decoration: pw.BoxDecoration(
                          color: PdfColors.grey200,
                        ),
                        children: [
                          pw.Text('SL', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                          pw.Text('Item Name', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                          pw.Text('Qty', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                          pw.Text('Unit', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                          pw.Text('Unit Price', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                          pw.Text('Total', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                          pw.Text('Date & Time', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                        ].map((text) => pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1), child: text)).toList(),
                      ),
                      // Table Rows
                      ...categoryItems.asMap().entries.map((item) => pw.TableRow(
                        children: [
                          pw.Text('${item.key + 1}', style: pw.TextStyle(fontSize: 8)),
                          pw.Text(item.value.name, style: pw.TextStyle(fontSize: 8)),
                          pw.Text('${item.value.quantity}', style: pw.TextStyle(fontSize: 8)),
                          pw.Text(item.value.unit, style: pw.TextStyle(fontSize: 8)),
                          pw.Text('${displayCurrency}${item.value.unitPrice.toStringAsFixed(1)}', style: pw.TextStyle(fontSize: 8)),
                          pw.Text('${displayCurrency}${item.value.price.toStringAsFixed(1)}', style: pw.TextStyle(fontSize: 8)),
                          pw.Text(DateFormat('dd/MM/yy HH:mm').format(item.value.doneTime!), style: pw.TextStyle(fontSize: 8)),
                        ].map((text) => pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1), child: text)).toList(),
                      )),
                    ],
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text('Subtotal (${entry.key}): ${displayCurrency}${subtotal.toStringAsFixed(1)}', 
                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 8),
                ],
              );
            }),

            // Summary
            pw.Divider(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Total Items: ${_boughtItems.length}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text('Grand Total: ${displayCurrency}${_calculateTotalAmount().toStringAsFixed(1)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ],
          footer: (context) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Page ${context.pageNumber} of ${context.pagesCount}'),
              pw.Container(
                width: 100,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text('Creator Signature:', style: pw.TextStyle(fontSize: 8)),
                    pw.SizedBox(height: 2),
                    pw.Container(
                      width: 100,
                      height: 30,
                      child: signatureImage != null
                          ? pw.Image(signatureImage, fit: pw.BoxFit.contain)
                          : pw.Container(),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(userName, style: pw.TextStyle(fontSize: 8)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

      // Create directory if it doesn't exist
      final baseDir = '/storage/emulated/0/Download/BazarHive by AHDS/Bought Reports';
      final directory = Directory(baseDir);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      // Save the PDF
      final file = File('$baseDir/$fileName');
      await file.writeAsBytes(await pdf.save());

      return 'Report saved successfully: $fileName';
    } catch (e) {
      return 'Error generating PDF: $e';
    }
  }

  @override
  void dispose() {
    // Dispose interstitial ad
    _adHelper.dispose();
    super.dispose();
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

  Widget _buildItemImage(ShoppingItem item) {
    if (item.imagePath == null || item.imagePath!.isEmpty) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Color(item.categoryColor).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: Icon(
          Icons.shopping_cart,
          color: Color(item.categoryColor),
          size: 20,
        ),
      );
    }

    final imageFile = File(item.imagePath!);
    if (!imageFile.existsSync()) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: const Icon(Icons.broken_image, color: Colors.grey, size: 20),
      );
    }

    return SizedBox(
      width: 40,
      height: 40,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8.0),
        child: Image.file(
          imageFile,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: const Icon(Icons.broken_image, color: Colors.grey, size: 20),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2196F3),
        elevation: 2,
        title: const Text(
          'Bought Report',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: <Widget>[
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: Theme.of(context).brightness == Brightness.dark
                        ? [
                            Colors.blue.shade900.withOpacity(0.2),
                            Colors.blue.shade800.withOpacity(0.3),
                          ]
                        : [
                            Colors.blue.shade50,
                            Colors.blue.shade100,
                          ],
                  ),
                ),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date Range Selection
                    Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            icon: const Icon(Icons.calendar_today),
                            label: Text(
                              _fromDateTime == null
                                  ? 'From Date & Time'
                                  : DateFormat('dd/MM/yyyy HH:mm').format(_fromDateTime!),
                            ),
                            onPressed: () => _selectDateTime(true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextButton.icon(
                            icon: const Icon(Icons.calendar_today),
                            label: Text(
                              _toDateTime == null
                                  ? 'To Date & Time'
                                  : DateFormat('dd/MM/yyyy HH:mm').format(_toDateTime!),
                            ),
                            onPressed: () => _selectDateTime(false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Category Selection
                    Row(
                      children: [
                        const Text(
                          'Categories:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade400),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: PopupMenuButton<String>(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _selectedCategories.isEmpty
                                            ? 'All Categories'
                                            : '${_selectedCategories.length} Selected',
                                        style: TextStyle(
                                          color: _selectedCategories.isEmpty
                                              ? Theme.of(context).brightness == Brightness.dark
                                                  ? Colors.grey.shade400
                                                  : Colors.grey.shade600
                                              : Theme.of(context).textTheme.bodyLarge?.color,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      Icons.arrow_drop_down,
                                      color: Colors.grey.shade600,
                                    ),
                                  ],
                                ),
                              ),
                              itemBuilder: (context) => [
                                // Individual categories
                                ..._categories.map((category) => PopupMenuItem<String>(
                                  value: category,
                                  child: StatefulBuilder(
                                    builder: (context, setState) => Row(
                                      children: [
                                        Checkbox(
                                          value: _selectedCategories.contains(category),
                                          onChanged: (bool? value) {
                                            setState(() {
                                              if (value == true) {
                                                _selectedCategories.add(category);
                                              } else {
                                                _selectedCategories.remove(category);
                                              }
                                            });
                                            this.setState(() {});
                                            _loadBoughtItems();
                                          },
                                        ),
                                        Text(category),
                                      ],
                                    ),
                                  ),
                                )),
                              ],
                              onSelected: (String value) {
                                setState(() {
                                  if (_selectedCategories.contains(value)) {
                                    _selectedCategories.remove(value);
                                  } else {
                                    _selectedCategories.add(value);
                                  }
                                });
                                _loadBoughtItems();
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Items List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _boughtItems.isEmpty
                      ? const Center(child: Text('No items found'))
                      : ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: _groupedItems.keys.length,
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
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        ListTile(
                                          leading: _buildItemImage(item),
                                          title: Text(
                                            item.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          subtitle: Consumer<CurrencyProvider>(
                                            builder: (context, currencyProvider, child) {
                                              return Row(
                                                crossAxisAlignment: CrossAxisAlignment.center,
                                                children: [
                                                  Icon(Icons.fiber_manual_record, size: 8, color: Colors.grey[700]),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      '${item.quantity} ${item.unit} × ${currencyProvider.selectedCurrency.symbol}${item.unitPrice} = ${currencyProvider.selectedCurrency.symbol}${item.price}',
                                                    ),
                                                  ),
                                                ],
                                              );
                                            },
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                                          color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.check_circle_outline, size: 16, color: Theme.of(context).colorScheme.primary),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Purchased: ${DateFormat('dd/MM/yyyy hh:mm a').format(item.doneTime!)}',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontStyle: FontStyle.italic,
                                                  fontWeight: FontWeight.w500,
                                                  color: Theme.of(context).colorScheme.primary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                ),
                              ),
                            );
                          },
                        ),
              ),
            const SizedBox(height: 16),
            // Summary Section
            Container(
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
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSavingPDF
                    ? null
                    : () async {
                        setState(() => _isSavingPDF = true);
                        try {
                          final message = await _generateAndSavePDF();
                          if (!mounted) return;
                          
                          // Show success message
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(message)),
                          );
                          
                          // Show interstitial ad after PDF is saved
                          await _showInterstitialAd();
                        } finally {
                          if (mounted) {
                            setState(() => _isSavingPDF = false);
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).brightness == Brightness.dark
                      ? Colors.green.shade700
                      : Colors.green.shade500,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: _isSavingPDF
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.picture_as_pdf),
                label: Text(
                  _isSavingPDF ? 'Saving...' : 'Save as PDF',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const BannerAdWidget(),
          ],
        ),
      ),
    );
  }
}
