import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'widgets/banner_ad_widget.dart';
import 'services/ad_helper.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'bought_item.dart';
import 'providers/theme_provider.dart';
import 'providers/currency_provider.dart';
import 'providers/security_provider.dart';
import 'database/database_helper.dart';
import 'dart:io' show Platform, InternetAddress, SocketException, File;
import 'dart:convert';
import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' if (dart.library.html) '';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'category_management_page.dart';
import 'pages/bought_report_page.dart';
import 'pages/about_page_bazarhive.dart';
import 'models/shopping_item.dart';
import 'models/category.dart' as models;
import 'widgets/add_item_dialog.dart';
import 'widgets/item_selection_dialog.dart';
import 'models/item.dart';
import 'widgets/edit_item_dialog.dart';
import 'widgets/drawer_profile_section.dart';
import 'widgets/import_list_dialog.dart';
import 'pages/profile_page.dart';
import 'pages/settings_screen.dart';
import 'services/event_bus.dart';
import 'pages/lock_screen.dart';
import 'screens/splash_screen.dart';
import 'pages/backup_screen.dart';
import 'pages/manage_items_page.dart';
import 'pages/onboarding_screen.dart';
import 'pages/initial_restore_page.dart';
import 'providers/google_drive_provider.dart';
import 'services/item_notifier.dart';
import 'services/category_notifier.dart';
import 'package:workmanager/workmanager.dart';
import 'services/backup_service.dart';
import 'dart:io';
import 'package:BazarHive/services/notification_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != 'auto_backup_task') return Future.value(true);

    final notificationService = NotificationService();
    bool localBackupSuccess = false;
    bool driveBackupSuccess = false;

    try {
      WidgetsFlutterBinding.ensureInitialized();
      await notificationService.init();
      final prefs = await SharedPreferences.getInstance();
      final dbHelper = DatabaseHelper();
      final backupService = BackupService(dbHelper, prefs);

      final backupPath = await backupService.createBackupFile(onProgress: (p, m) {});
      if (backupPath == null) {
        await notificationService.showNotification(1, 'Backup Failed', 'Could not create temporary backup file.');
        return false;
      }

      // --- Attempt Local Backup ---
      try {
        final publicPath = await backupService.saveBackupFileToPublicLocation(backupPath);
        await notificationService.showNotification(0, 'Local Backup Successful', 'Backup saved to ${publicPath.split('/').last}');
        await prefs.setString('lastLocalBackup', DateTime.now().toIso8601String());
        localBackupSuccess = true;
      } catch (e) {
        await notificationService.showNotification(1, 'Local Backup Failed', e.toString());
      }

      // --- Attempt Google Drive Backup ---
      final driveService = GoogleDriveService();
      await driveService.signInSilently();
      if (driveService.currentUser != null) {
        try {
          await driveService.uploadBackup(backupPath);
          await notificationService.showNotification(2, 'Google Drive Backup Successful', 'Your data has been backed up to Google Drive.');
          await prefs.setString('lastGoogleDriveBackup', DateTime.now().toIso8601String());
          driveBackupSuccess = true;
        } catch (e) {
          await notificationService.showNotification(3, 'Google Drive Backup Failed', e.toString());
        }
      }

      // --- Cleanup and Signal UI ---
      await File(backupPath).delete();
      if (localBackupSuccess || driveBackupSuccess) {
        final directory = await getApplicationDocumentsDirectory();
        final signalFile = File(path.join(directory.path, 'backup.signal'));
        await signalFile.create();
        return true;
      }

      return false; // Return false if both backups failed

    } catch (e) {
      await notificationService.showNotification(4, 'Backup Failed', 'An unexpected error occurred: ${e.toString()}');
      return false;
    }
  });
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
bool _appInitialized = false;

void main() async {
  if (_appInitialized) return;
  _appInitialized = true;

  // Initialize Flutter bindings
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize Firebase
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'AIzaSyAoRhkko1-mo6E0-KlV7QCJuMQs5mpZ1yA',
        appId: '1:920171293642:android:4a42faa87d940e53573d33',
        messagingSenderId: '920171293642',
        projectId: 'bazarhive-a4bf2',
        storageBucket: 'bazarhive-a4bf2.firebasestorage.app',
      ),
    );
  } catch (e) {
    debugPrint('Error initializing Firebase: $e');
  }

  // Initialize FFI for sqflite on desktop platforms
  if (!Platform.isAndroid && !Platform.isIOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Initialize Notifications
  await NotificationService().init();
  
  // Initialize Mobile Ads SDK
  await MobileAds.instance.initialize();

  // Initialize WorkManager
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

  // Run the app
  final prefs = await SharedPreferences.getInstance();
  final secureStorage = const FlutterSecureStorage();
  final localAuth = LocalAuthentication();

  runApp(
    MultiProvider(
      providers: [
        // Existing Providers
        ChangeNotifierProvider(create: (_) => ThemeProvider(prefs)),
        ChangeNotifierProvider(create: (_) => CurrencyProvider(prefs)),
        ChangeNotifierProvider(create: (_) => SecurityProvider(prefs, secureStorage, localAuth)),

        // Add missing providers required by InitialRestorePage and other parts of the app
        Provider<DatabaseHelper>(create: (_) => DatabaseHelper()),
        Provider<SharedPreferences>.value(value: prefs),
        Provider(create: (_) => GoogleDriveService()),
        Provider(create: (context) => BackupService(context.read<DatabaseHelper>(), context.read<SharedPreferences>())),

      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return MaterialApp(
      navigatorKey: navigatorKey,
      themeMode: themeProvider.themeMode,
      title: 'BazarHive',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
      routes: {
        '/lock': (context) => LockScreen(
              onUnlocked: () {
                Navigator.pushReplacementNamed(context, '/home');
              },
            ),
        '/onboarding': (context) => OnboardingScreen(
              onComplete: () {
                Navigator.pushReplacementNamed(context, '/home');
              },
            ),

        '/home': (context) => const MyHomePage(),
        '/profile': (context) => const ProfilePage(),
        '/settings': (context) => const SettingsScreen(),
        '/backup': (context) => const BackupScreen(),
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  String _formatDateTime(DateTime dateTime) {
    final hour = dateTime.hour;
    final period = hour < 12 ? 'AM' : 'PM';
    final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${hour12.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')} $period';
  }

  final DatabaseHelper _databaseHelper = DatabaseHelper();
  final List<ShoppingItem> _items = [];
  SharedPreferences? _prefs;
  Map<String, models.Category> _categories = <String, models.Category>{};
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AppLinks _appLinks = AppLinks();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showBoughtItems = true;
  bool _isSearching = false;
  bool _isLoading = true;
  StreamSubscription? _dataResetSubscription;
  bool _isProcessingLink = false;

  // Interstitial ad helper
  final InterstitialAdHelper _adHelper = InterstitialAdHelper();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    _setupAppLinks();

    // Listen for item and category updates to refresh the home screen
    ItemNotifier.instance.addListener(_loadData);
    CategoryNotifier.instance.addListener(_loadData);

    // Listen for data reset events
    _dataResetSubscription = EventBus.on<DataResetEvent>().listen((event) {
      if (event.type == 'shopping_items' || event.type == 'full_reset') {
        setState(() {
          _items.clear();
        });
        _loadData();
      }
    });

    // Load interstitial ad
    _adHelper.loadAd();
  }

  Future<void> _loadData() async {
    _prefs = await SharedPreferences.getInstance();
    final String? itemsJson = _prefs?.getString('shopping_items');
    
    if (itemsJson != null) {
      final List<dynamic> decoded = jsonDecode(itemsJson);
      setState(() {
        _items.clear();
        _items.addAll(decoded.map((item) => ShoppingItem.fromJson(item)));
      });
    }

    // Load categories
    final categories = await _databaseHelper.getCategories();
    setState(() {
      _categories = {for (var c in categories) c.id.toString(): c};
    });
  }

  Future<void> _saveItems() async {
    if (_prefs == null) {
      _prefs = await SharedPreferences.getInstance();
    }
    final String encoded = jsonEncode(_items.map((item) => item.toJson()).toList());
    await _prefs?.setString('shopping_items', encoded);
  }

  Map<int?, List<ShoppingItem>> _groupedItems() {
    Map<int?, List<ShoppingItem>> grouped = {};

    for (var item in _items) {
      // Use categoryId for grouping. null represents 'Uncategorized'.
      int? categoryId = item.categoryId;
      if (!grouped.containsKey(categoryId)) {
        grouped[categoryId] = [];
      }
      grouped[categoryId]!.add(item);
    }

    // Create a sorted list of keys
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) {
        if (a == null) return -1; // Uncategorized first
        if (b == null) return 1;
        // Sort by category name
        final nameA = _categories[a.toString()]?.name.toLowerCase() ?? '';
        final nameB = _categories[b.toString()]?.name.toLowerCase() ?? '';
        return nameA.compareTo(nameB);
      });

    // Create a new sorted map
    final sortedGrouped = <int?, List<ShoppingItem>>{};
    for (var key in sortedKeys) {
      sortedGrouped[key] = grouped[key]!;
    }

    return sortedGrouped;
  }

  // Toggle the bought status of an item and update its doneTime
  Future<void> _toggleItemStatus(ShoppingItem item) async {
    // Show confirmation dialog only when unchecking an item
    if (item.isBought) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Mark as Not Bought?'),
          content: Text('Do you want to move "${item.name}" back to the shopping list?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Move Back'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    final newIsBought = !item.isBought;
    // If marking as bought, keep existing time or set to now. If un-marking, clear the time.
    final newDoneTime = newIsBought ? (item.doneTime ?? DateTime.now()) : null;

    final updatedItem = item.copyWith(
      isBought: newIsBought,
      doneTime: newDoneTime,
    );

    setState(() {
      final index = _items.indexOf(item);
      if (index != -1) {
        _items[index] = updatedItem;
      }
    });
    _saveItems(); // Save items after updating status
  }
  
  // Edit an existing item
  Future<void> _finishShopping() async {
    final boughtItemsCheck = _items.where((item) => item.isBought).toList();
    if (boughtItemsCheck.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No bought items to finish!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Build the summary of bought items
    final currencySymbol = Provider.of<CurrencyProvider>(context, listen: false).selectedCurrency.symbol;
    final itemsSummary = StringBuffer();
    double totalAmount = 0.0;

    for (var item in boughtItemsCheck) {
      itemsSummary.writeln('• ${item.name}: ${item.quantity} ${item.unit} × $currencySymbol${item.unitPrice.toStringAsFixed(2)} = $currencySymbol${item.price.toStringAsFixed(2)}');
      totalAmount += item.price;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finish Shopping'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Move ${boughtItemsCheck.length} bought items to history?'),
            const SizedBox(height: 16),
            const Text('Summary:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.3,
              ),
              child: SingleChildScrollView(
                child: Text(itemsSummary.toString()),
              ),
            ),
            const SizedBox(height: 8),
            Text('Total: $currencySymbol${totalAmount.toStringAsFixed(2)}',
                 style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Move'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Re-fetch the list of bought items to ensure it has the latest data
      final boughtItems = _items.where((item) => item.isBought).toList();

      // Convert items to database format
      final itemsForDb = boughtItems.map((item) => {
        'name': item.name,
        'quantity': item.quantity,
        'unit': item.unit,
        'price': item.price,
        'category': item.category,
        'categoryColor': item.categoryColor,
        'unitPrice': item.unitPrice,
        'imagePath': item.imagePath,
        'date': item.doneTime!.millisecondsSinceEpoch, // Corrected key
      }).toList();

      // Save to bought items table
      await _databaseHelper.saveBoughtItems(itemsForDb);

      // Remove items from current list
      setState(() {
        _items.removeWhere((item) => item.isBought);
      });
      _saveItems();

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Items moved to bought items history'),
            backgroundColor: Colors.green,
          ),
        );

        // Show interstitial ad after finishing shopping
        await _showInterstitialAd();
      }
    }
  }

  Future<void> _deleteItem(ShoppingItem item) async {
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
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _items.remove(item);
      });
      _saveItems();
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
      final quantity = result['quantity'] as double;
      final unitPrice = result['unitPrice'] as double;
      final category = result['category'] as String;
      final categoryId = result['categoryId'] as int?;
      final categoryColor = result['categoryColor'] as int;
      final doneTime = result['doneTime'] as DateTime?;
      
      setState(() {
        // Find and replace the item in the list
        final index = _items.indexOf(item);
        if (index != -1) {
          _items[index] = ShoppingItem(
            name: item.name,
            quantity: quantity,
            unit: item.unit,
            price: quantity * unitPrice,
            category: category,
            categoryId: categoryId,
            isBought: item.isBought,
            doneTime: doneTime,
            categoryColor: categoryColor,
            unitPrice: unitPrice,
          );
        }
      });
      _saveItems(); // Save items after editing
    }
  }

  Set<String> _getExistingCategories() {
    return _items.map((item) => item.category).where((cat) => cat.isNotEmpty).toSet();
  }

  // Calculate total cost of all items
  double _calculateTotal() {
    return _items.fold(0, (sum, item) => sum + item.price);
  }

  // Calculate total cost of bought items
  double _calculateBoughtTotal() {
    return _items
        .where((item) => item.isBought)
        .fold(0, (sum, item) => sum + item.price);
  }

  // Calculate total cost of pending items
  double _calculatePendingTotal() {
    return _items
        .where((item) => !item.isBought)
        .fold(0, (sum, item) => sum + item.price);
  }

  void _showAddItemDialog() async {
    // Step 1: Show item selection dialog
    final selectedItem = await showDialog<Item>(
      context: context,
      builder: (context) => const ItemSelectionDialog(),
    );

    // If an item is selected (either existing or newly created from the selection dialog)
    if (selectedItem != null) {
      // Step 2: Show the AddItemDialog pre-filled with the selected item's data
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AddItemDialog(item: selectedItem),
      );

      if (result != null) {
        final newItem = ShoppingItem(
          name: result['name'],
          quantity: result['quantity'],
          unit: result['unit'],
          price: result['price'],
          category: result['category_name'],
          categoryId: result['category_id'],
          categoryColor: result['category_color'],
          unitPrice: result['price'] / result['quantity'],
          imagePath: result['imagePath'],
        );
        setState(() {
          _items.add(newItem);
        });
        _saveItems();
        _calculateTotal();
      }
    }
  }

  Future<void> _showShareDialog() async {
    // Get non-purchased items
    final unpurchasedItems = _items.where((item) => !item.isBought).toList();
    if (unpurchasedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No unpurchased items to share')),
      );
      return;
    }

    // Create a set to track selected items
    final selectedItems = <ShoppingItem>{};
    bool selectAll = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Select Items to Share'),
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
                          selectedItems.addAll(unpurchasedItems);
                        } else {
                          selectedItems.clear();
                        }
                      });
                    },
                  ),
                  const Divider(),
                  for (var item in unpurchasedItems)
                    CheckboxListTile(
                      title: Text(item.name),
                      subtitle: Consumer<CurrencyProvider>(
                        builder: (context, currencyProvider, child) => Text(
                          '${item.quantity} ${item.unit} - ${currencyProvider.selectedCurrency.symbol}${item.unitPrice} each',
                        ),
                      ),
                      value: selectedItems.contains(item),
                      onChanged: (bool? value) {
                        setState(() {
                          if (value == true) {
                            selectedItems.add(item);
                            if (selectedItems.length == unpurchasedItems.length) {
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
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
              onPressed: () async {
                if (selectedItems.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please select at least one item')),
                  );
                  return;
                }
                
                // Show loading dialog
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          const Text('Preparing share message...'),
                        ],
                      ),
                    );
                  },
                );
                
                try {
                  final selectedItemsList = selectedItems.toList();

                  // Get user's profile name
                  final prefs = await SharedPreferences.getInstance();
                  final userName = prefs.getString('userName') ?? 'Unknown User';

                  // Get currency symbol
                  final currencyProvider = Provider.of<CurrencyProvider>(context, listen: false);
                  final currencySymbol = currencyProvider.selectedCurrency.symbol;

                  // Create formatted text message
                  final StringBuffer messageBuffer = StringBuffer();
                  messageBuffer.writeln('🛒 Shopping List from $userName');
                  messageBuffer.writeln('The listed prices are my expected estimates — slight variations are absolutely fine.\n');
                  
                  double total = 0;
                  for (var item in selectedItemsList) {
                    final itemTotal = item.quantity * item.unitPrice;
                    total += itemTotal;
                    messageBuffer.writeln(
                      '• ${item.name}: ${item.quantity} ${item.unit} × $currencySymbol${item.unitPrice} = $currencySymbol${itemTotal}'
                    );
                  }
                  
                  messageBuffer.writeln('\n🧾 Total: $currencySymbol$total');
                  
                  // Check for internet connection
                  bool hasInternet = false;
                  try {
                    final result = await InternetAddress.lookup('google.com');
                    hasInternet = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
                  } on SocketException catch (_) {
                    hasInternet = false;
                  }
                  
                  if (hasInternet) {
                    // Create items JSON for Firestore
                    final itemsJson = selectedItemsList.map((item) => {
                      'itemName': item.name,
                      'quantity': item.quantity,
                      'unit': item.unit,
                      'unitPrice': item.unitPrice,
                      'totalPrice': item.quantity * item.unitPrice,
                    }).toList();

                    // Save to Firestore
                    final docRef = await _firestore.collection('shared_lists').add({
                      'ownerName': userName,
                      'createdAt': FieldValue.serverTimestamp(),
                      'items': itemsJson,
                    });
                    
                    // Add import link only when online
                    messageBuffer.writeln('\n📥 Import this list in BazarHive App:');
                    messageBuffer.writeln('https://bazarhive-a4bf2.web.app/redirect.html?id=${docRef.id}');
                  }

                  // Close loading dialog
                  Navigator.of(context).pop();
                  
                  // Close the item selection dialog
                  Navigator.of(context).pop();
                  
                  // Share the message
                  await Share.share(messageBuffer.toString());
                } catch (e) {
                  // Close loading dialog if there's an error
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error sharing list: ${e.toString()}')),
                  );
                }
                },
                child: const Text('Share'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _dataResetSubscription?.cancel();

    // Remove listeners to prevent memory leaks
    ItemNotifier.instance.removeListener(_loadData);
    CategoryNotifier.instance.removeListener(_loadData);

    // Remove widget binding observer
    WidgetsBinding.instance.removeObserver(this);

    // Dispose ad helper
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

  Future<void> _setupAppLinks() async {
    try {
      // Listen to incoming links when app is in foreground
      _appLinks.uriLinkStream.listen((uri) {
        if (mounted) {
          _handleLink(uri);
        }
      }, onError: (err) {
        debugPrint('Error handling app links: $err');
      });
    } catch (e) {
      debugPrint('Error setting up app links: $e');
    }
  }

  Future<void> _handleInitialUri() async {
    try {
      // Get the link that launched the app
      final appLink = await _appLinks.getInitialLink();
      if (appLink != null && mounted) {
        _handleLink(appLink);
      }
    } catch (e) {
      debugPrint('Error handling initial uri: $e');
    }
  }

  Future<void> _handleLink(Uri? uri) async {
    if (_isProcessingLink) return; // Prevent re-entrant calls
    if (uri == null) return;

    setState(() {
      _isProcessingLink = true;
    });

    try {

    // Ensure the widget is mounted and we have a navigator context
    if (!mounted) return;
    final BuildContext? navContext = navigatorKey.currentContext;
    if (navContext == null) return;

    if (uri.scheme == 'bazarhive' && uri.host == 'import') {
      final id = uri.queryParameters['id'];
      if (id != null) {
        showDialog(
          context: navContext,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return const Dialog(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(width: 20),
                    Text("Loading list..."),
                  ],
                ),
              ),
            );
          },
        );
        try {
          final doc =
              await _firestore.collection('shared_lists').doc(id).get();
          Navigator.of(navContext).pop(); // Dismiss loading dialog
          if (!doc.exists) {
            ScaffoldMessenger.of(navContext).showSnackBar(
              const SnackBar(content: Text('Shared list not found')),
            );
            return;
          }

          final data = doc.data()!;
          final ownerName = data['ownerName'] as String;
          final items =
              List<Map<String, dynamic>>.from(data['items'] as List);

          await showDialog(
            context: navContext,
            builder: (dialogContext) => ImportListDialog(
              ownerName: ownerName,
              items: items,
              onImport: (categoryName, color, importedItems) async {
                final category = await _databaseHelper
                    .ensureCategoryExists(categoryName, color);

                final List<ShoppingItem> newItems = [];
                for (var itemData in items) {
                  final newItem = ShoppingItem(
                    name: itemData['itemName'],
                    quantity: (itemData['quantity'] as num).toDouble(),
                    unit: itemData['unit'],
                    price: 0,
                    unitPrice: (itemData['unitPrice'] as num).toDouble(),
                    category: category.name,
                    categoryId: category.id,
                    categoryColor: category.color.value,
                    isBought: false,
                  );
                  newItems.add(newItem);
                }

                if (mounted) {
                  setState(() {
                    _items.addAll(newItems);
                  });
                }
                
                _saveItems();

                // Use the navigator context for the SnackBar
                final postImportContext = navigatorKey.currentContext;
                if (postImportContext != null && mounted) {
                  ScaffoldMessenger.of(postImportContext).showSnackBar(
                    SnackBar(
                        content: Text(
                            'Imported ${newItems.length} items into "${category.name}" ')),
                  );
                }
              },
            ),
          );
        } catch (e) {
          Navigator.of(navContext).pop(); // Dismiss loading dialog on error
          ScaffoldMessenger.of(navContext).showSnackBar(
            const SnackBar(content: Text('Error importing shared list')),
          );
          debugPrint('Error importing shared list: $e');
        }
      }
    }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingLink = false;
        });
      }
    }
  }

  Future<void> _changePurchaseDateTime(ShoppingItem item) async {
    final newDate = await showDatePicker(
      context: context,
      initialDate: item.doneTime ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (newDate == null) return;

    final newTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(item.doneTime ?? DateTime.now()),
    );

    if (newTime != null) {
      final newDateTime = DateTime(
        newDate.year,
        newDate.month,
        newDate.day,
        newTime.hour,
        newTime.minute,
      );

      // Create an updated item using copyWith
      final updatedItem = item.copyWith(doneTime: newDateTime);

      setState(() {
        final index = _items.indexOf(item);
        if (index != -1) {
          // Replace the old item with the updated one
          _items[index] = updatedItem;
        }
      });
      _saveItems();
    }
  }

  Widget _buildItemImage(ShoppingItem item) {
    final placeholder = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Icon(
        Icons.shopping_cart,
        color: Theme.of(context).colorScheme.primary,
        size: 24,
      ),
    );

    if (item.imagePath != null && item.imagePath!.isNotEmpty) {
      final file = File(item.imagePath!);
      if (file.existsSync()) {
        return SizedBox(
          width: 40,
          height: 40,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8.0),
            child: Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => placeholder,
            ),
          ),
        );
      }
    }
    return placeholder;
  }

  @override
  Widget build(BuildContext context) {
    final groupedItems = _groupedItems();
    final categoryIds = groupedItems.keys.toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        title: const Text(
          'BazarHive',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.backup, color: Colors.white),
            onPressed: () => Navigator.pushNamed(context, '/backup'),
          ),
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            // Fixed sections (non-scrollable)
            const DrawerProfileSection(),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.primary.withOpacity(0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.shopping_bag_outlined,
                        color: Colors.white,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'BazarHive',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Shopping List Manager',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            // Scrollable menu items
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: Icon(Icons.list_alt, color: Colors.blue.shade800),
                        title: Text('Items List',
                          style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.w500),
                        ),
                        onTap: () {
                          Navigator.pop(context); // Close drawer
                        },
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: Icon(Icons.category, color: Colors.orange.shade800),
                        title: Text('Manage Categories', 
                          style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.w500),
                        ),
                        onTap: () {
                          Navigator.pop(context); // Close drawer
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const CategoryManagementPage(),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.teal.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: Icon(Icons.list, color: Colors.teal.shade800),
                        title: Text('Manage Items',
                          style: TextStyle(color: Colors.teal.shade800, fontWeight: FontWeight.w500),
                        ),
                        onTap: () {
                          Navigator.pop(context); // Close drawer
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ManageItemsPage(),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: Icon(Icons.shopping_cart_checkout, color: Colors.green.shade800),
                        title: Text('Bought Items',
                          style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.w500),
                        ),
                        onTap: () {
                          Navigator.pop(context); // Close drawer
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const BoughtItemsPage(),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: Icon(Icons.assessment, color: Colors.blue.shade800),
                        title: Text('Bought Report',
                          style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.w500),
                        ),
                        onTap: () {
                          Navigator.pop(context); // Close drawer
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const BoughtReportPage(),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.purple.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: Icon(Icons.info_outline, color: Colors.purple.shade800),
                        title: Text('About',
                          style: TextStyle(color: Colors.purple.shade800, fontWeight: FontWeight.w500),
                        ),
                        onTap: () {
                          Navigator.pop(context); // Close drawer
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const AboutPageBazarHive(),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shopping_basket_outlined,
                          size: 80,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Your Shopping List is Empty',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Tap the + button to start adding items.',
                          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 40),
                        const Text(
                          'Welcome to BazarHive!\n\nThis app helps you manage your shopping lists. For your data safety, BazarHive can back up your lists to your personal Google Drive. It will only access files created by itself and will not access any other files.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: Colors.grey, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: categoryIds.length,
                  itemBuilder: (context, index) {
                final categoryId = categoryIds[index];
                final categoryItems = groupedItems[categoryId]!;

                final categoryInfo = (categoryId == null)
                    ? null
                    : _categories[categoryId.toString()];

                final categoryName = categoryInfo?.name ?? 'Uncategorized';
                final categoryColor = categoryInfo?.color ?? Colors.grey;
                final categoryImagePath = categoryInfo?.imagePath;

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      backgroundColor: categoryColor.withOpacity(0.2),
                      collapsedBackgroundColor: categoryColor.withOpacity(0.2),
                      title: Row(
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: categoryColor,
                            backgroundImage: (categoryImagePath != null && categoryImagePath.isNotEmpty)
                                ? FileImage(File(categoryImagePath))
                                : null,
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            categoryName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Status indicators aligned to the right
                        // Bought items count
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_box,
                              size: 16,
                              color: Colors.green[700],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              categoryItems.where((item) => item.isBought).length.toString(),
                              style: TextStyle(
                                color: Colors.green[700],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        // Remaining items count
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_box_outline_blank,
                              size: 16,
                              color: Colors.red[700],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              categoryItems.where((item) => !item.isBought).length.toString(),
                              style: TextStyle(
                                color: Colors.red[700],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    children: [
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: categoryItems.length,
                        itemBuilder: (context, itemIndex) {
                          final item = categoryItems[itemIndex];
                          return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                              elevation: 1,
                              clipBehavior: Clip.antiAlias, // To ensure the tag corner is clipped
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Stack(
                                children: <Widget>[
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      ListTile(
                                        contentPadding: const EdgeInsets.fromLTRB(16, 12, 48, 12),
                                        leading: _buildItemImage(item),
                                        title: Text(
                                          item.name,
                                          style: TextStyle(
                                            decoration: item.isBought ? TextDecoration.lineThrough : TextDecoration.none,
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
                                            Consumer<CurrencyProvider>(
                                              builder: (context, currencyProvider, child) => Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const SizedBox(height: 2),
                                                  Row(
                                                    children: [
                                                      Icon(Icons.monetization_on_outlined, size: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                                                      const SizedBox(width: 6),
                                                      Expanded(
                                                        child: Text(
                                                          'Unit Price: ${currencyProvider.selectedCurrency.symbol}${item.unitPrice.toStringAsFixed(2)}',
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            color: Theme.of(context).colorScheme.onSurface,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Row(
                                                    children: [
                                                      Icon(Icons.calculate_outlined, size: 14, color: Color(item.categoryColor)),
                                                      const SizedBox(width: 6),
                                                      Expanded(
                                                        child: Text(
                                                          'Total: ${currencyProvider.selectedCurrency.symbol}${item.price.toStringAsFixed(2)}',
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            fontWeight: FontWeight.bold,
                                                            color: Color(item.categoryColor),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (item.isBought && item.doneTime != null)
                                        GestureDetector(
                                          onTap: () => _changePurchaseDateTime(item),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                                            color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.check_circle_outline, size: 16, color: Theme.of(context).colorScheme.primary),
                                                const SizedBox(width: 8),
                                                Text(
                                                  'Purchased: ${_formatDateTime(item.doneTime!)}',
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
                                        ),
                                    ],
                                  ),
                                  Positioned(
                                    top: 0,
                                    bottom: 0,
                                    right: 0,
                                    child: PopupMenuButton<String>(
                                      onSelected: (value) {
                                        if (value == 'edit') {
                                          _editItem(item);
                                        } else if (value == 'change_date') {
                                          _changePurchaseDateTime(item);
                                        } else if (value == 'delete') {
                                          _deleteItem(item);
                                        }
                                      },
                                      itemBuilder: (BuildContext context) {
                                        return <PopupMenuEntry<String>>[
                                          PopupMenuItem<String>(
                                            value: 'edit',
                                            child: Row(children: const [
                                              Icon(Icons.edit, size: 20),
                                              SizedBox(width: 12),
                                              Text('Edit')
                                            ]),
                                          ),
                                          if (item.isBought)
                                            PopupMenuItem<String>(
                                              value: 'change_date',
                                              child: Row(children: const [
                                                Icon(Icons.calendar_today, size: 20),
                                                SizedBox(width: 12),
                                                Text('Change Date')
                                              ]),
                                            ),
                                          PopupMenuItem<String>(
                                            value: 'delete',
                                            child: Row(children: const [
                                              Icon(Icons.delete, color: Colors.red, size: 20),
                                              SizedBox(width: 12),
                                              Text('Delete', style: TextStyle(color: Colors.red))
                                            ]),
                                          ),
                                        ];
                                      },
                                      icon: const Icon(Icons.more_vert),
                                      tooltip: 'More options',
                                      padding: EdgeInsets.zero,
                                    ),
                                  ),
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    child: InkWell(
                                      onTap: () => _toggleItemStatus(item),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: item.isBought
                                              ? Colors.green.withOpacity(0.9)
                                              : Colors.blueGrey.withOpacity(0.7),
                                          borderRadius: const BorderRadius.only(
                                            topRight: Radius.circular(12.0),
                                            bottomLeft: Radius.circular(12.0),
                                          ),
                                        ),
                                        child: Text(
                                          item.isBought ? 'Bought' : 'Not Bought',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ]
                              ),
                            );

                        },
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
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total:',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Consumer<CurrencyProvider>(
                          builder: (context, currencyProvider, child) => Text(
                            '${currencyProvider.selectedCurrency.symbol}${(_calculateBoughtTotal() + _calculatePendingTotal()).toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Bought:',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                        Row(
                          children: [
                            Consumer<CurrencyProvider>(
                              builder: (context, currencyProvider, child) => Text(
                                '${currencyProvider.selectedCurrency.symbol}${_calculateBoughtTotal().toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: Colors.green[700],
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 14,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Remaining:',
                          style: TextStyle(
                            color: Colors.orange[700],
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                        Row(
                          children: [
                            Consumer<CurrencyProvider>(
                              builder: (context, currencyProvider, child) => Text(
                                '${currencyProvider.selectedCurrency.symbol}${_calculatePendingTotal().toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: Colors.orange[700],
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(
                              Icons.pending_outlined,
                              color: Colors.orange,
                              size: 14,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.25),
                            spreadRadius: 1,
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        onPressed: () => _finishShopping(),
                        icon: const Icon(Icons.check_circle),
                        iconSize: 20,
                        color: Colors.white,
                        padding: const EdgeInsets.all(2),
                        constraints: const BoxConstraints(),
                        tooltip: 'Finish Shopping',
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text('Finish\nShopping', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.1)),
                  ],
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.25),
                            spreadRadius: 1,
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        onPressed: _showShareDialog,
                        icon: const Icon(Icons.share),
                        iconSize: 20,
                        color: Colors.white,
                        padding: const EdgeInsets.all(2),
                        constraints: const BoxConstraints(),
                        tooltip: 'Share Items',
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text('Share\nItems', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.1)),
                  ],
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.purple,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.25),
                            spreadRadius: 1,
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        onPressed: _showAddItemDialog,
                        icon: const Icon(Icons.add),
                        iconSize: 20,
                        color: Colors.white,
                        padding: const EdgeInsets.all(2),
                        constraints: const BoxConstraints(),
                        tooltip: 'Add Item',
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text('Add\nItem', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.1)),
                  ],
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.25),
                            spreadRadius: 1,
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: PopupMenuButton<String>(
                        onSelected: (String result) {
                          switch (result) {
                            case 'category':
                              Navigator.push(context, MaterialPageRoute(builder: (context) => const CategoryManagementPage()));
                              break;
                            case 'items':
                              Navigator.push(context, MaterialPageRoute(builder: (context) => const ManageItemsPage()));
                              break;
                            case 'bought_items':
                              Navigator.push(context, MaterialPageRoute(builder: (context) => const BoughtItemsPage()));
                              break;
                            case 'bought_report':
                              Navigator.push(context, MaterialPageRoute(builder: (context) => const BoughtReportPage()));
                              break;
                          }
                        },
                        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                          const PopupMenuItem<String>(
                            value: 'category',
                            child: Row(
                              children: [
                                Icon(Icons.category_outlined, size: 20),
                                SizedBox(width: 12),
                                Text('Categories'),
                              ],
                            ),
                          ),
                          const PopupMenuItem<String>(
                            value: 'items',
                            child: Row(
                              children: [
                                Icon(Icons.list_alt_outlined, size: 20),
                                SizedBox(width: 12),
                                Text('Manage Items'),
                              ],
                            ),
                          ),
                          const PopupMenuItem<String>(
                            value: 'bought_items',
                            child: Row(
                              children: [
                                Icon(Icons.history_outlined, size: 20),
                                SizedBox(width: 12),
                                Text('Bought History'),
                              ],
                            ),
                          ),
                          const PopupMenuItem<String>(
                            value: 'bought_report',
                            child: Row(
                              children: [
                                Icon(Icons.assessment_outlined, size: 20),
                                SizedBox(width: 12),
                                Text('Bought Report'),
                              ],
                            ),
                          ),
                        ],
                        icon: const Icon(Icons.apps_outlined, color: Colors.white, size: 20),
                        padding: const EdgeInsets.all(2),
                        constraints: const BoxConstraints(),
                        tooltip: 'Manage',
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text('Manage', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.1)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            const BannerAdWidget()
          ],
        ),
      ),
    );
  }
}
