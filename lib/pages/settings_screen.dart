import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter_phoenix/flutter_phoenix.dart';
import '../providers/theme_provider.dart';
import '../providers/currency_provider.dart';
import '../providers/security_provider.dart';
import '../widgets/banner_ad_widget.dart';
import '../database/database_helper.dart';
import '../services/event_bus.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<bool> _isBiometricAvailableFuture;

  @override
  void initState() {
    super.initState();
    final securityProvider = Provider.of<SecurityProvider>(context, listen: false);
    _isBiometricAvailableFuture = securityProvider.checkBiometricAvailable();
  }

  final TextEditingController _searchController = TextEditingController();
  List<Currency> _filteredCurrencies = [];
  String _selectedLanguage = 'English';
  TextEditingController _pinController = TextEditingController();
  String _errorMessage = '';
  final DatabaseHelper _databaseHelper = DatabaseHelper();

  Future<void> _showSetPinDialog(BuildContext context, {bool isChange = false}) async {
    _pinController.clear();
    _errorMessage = '';
    String? firstPin;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(isChange ? 'Change PIN' : 'Set PIN'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _pinController,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    obscureText: true,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: '****',
                      labelText: firstPin == null ? 'Enter PIN' : 'Confirm PIN',
                      errorText: _errorMessage.isNotEmpty ? _errorMessage : null,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    if (!isChange) {
                      final securityProvider = Provider.of<SecurityProvider>(context, listen: false);
                      securityProvider.setAppLockEnabled(false);
                    }
                  },
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    if (_pinController.text.length != 4) {
                      setState(() => _errorMessage = 'PIN must be 4 digits');
                      return;
                    }

                    if (firstPin == null) {
                      firstPin = _pinController.text;
                      _pinController.clear();
                      setState(() => _errorMessage = '');
                    } else if (_pinController.text == firstPin) {
                      final securityProvider = Provider.of<SecurityProvider>(context, listen: false);
                      await securityProvider.setPin(firstPin!);
                      if (!isChange) {
                        await securityProvider.setAppLockEnabled(true);
                      }
                      if (mounted) {
                        Navigator.of(context).pop();
                      }
                    } else {
                      firstPin = null;
                      _pinController.clear();
                      setState(() => _errorMessage = 'PINs do not match');
                    }
                  },
                  child: Text(firstPin == null ? 'Next' : 'Confirm'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Method to show reset options dialog with checkboxes
  Future<void> _showResetOptionsDialog(BuildContext context) async {
    // Reset options state
    bool resetHomepageUndoneItems = false;
    bool resetHomepageDoneItems = false;
    bool resetBoughtItemPageItems = false;
    bool resetFullApp = false;

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Reset Options'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select the data you want to reset:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    title: const Text('Homepage Undone Items'),
                    value: resetHomepageUndoneItems,
                    enabled: !resetFullApp,
                    onChanged: (value) {
                      setState(() {
                        resetHomepageUndoneItems = value ?? false;
                      });
                    },
                  ),
                  CheckboxListTile(
                    title: const Text('Homepage Done Items'),
                    value: resetHomepageDoneItems,
                    enabled: !resetFullApp,
                    onChanged: (value) {
                      setState(() {
                        resetHomepageDoneItems = value ?? false;
                      });
                    },
                  ),
                  CheckboxListTile(
                    title: const Text('Bought Item Page Items'),
                    value: resetBoughtItemPageItems,
                    enabled: !resetFullApp,
                    onChanged: (value) {
                      setState(() {
                        resetBoughtItemPageItems = value ?? false;
                      });
                    },
                  ),
                  const Divider(),
                  CheckboxListTile(
                    title: const Text(
                      'Full App Reset',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    subtitle: const Text(
                      'Deletes all user data and resets the app',
                      style: TextStyle(color: Colors.red),
                    ),
                    value: resetFullApp,
                    onChanged: (value) {
                      setState(() {
                        resetFullApp = value ?? false;
                        // If full reset is selected, select all other options
                        if (resetFullApp) {
                          resetHomepageUndoneItems = true;
                          resetHomepageDoneItems = true;
                          resetBoughtItemPageItems = true;
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  // Check if at least one option is selected
                  if (!resetHomepageUndoneItems && 
                      !resetHomepageDoneItems && 
                      !resetBoughtItemPageItems && 
                      !resetFullApp) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please select at least one option'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }
                  
                  // Close the dialog
                  Navigator.of(dialogContext).pop();
                  
                  // Perform the reset operations
                  await _performReset(
                    resetHomepageUndoneItems,
                    resetHomepageDoneItems,
                    resetBoughtItemPageItems,
                    resetFullApp,
                  );
                  
                  // Show confirmation message
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Selected data has been deleted'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                  
                  // If full app reset, restart the app
                  if (resetFullApp && mounted) {
                    Phoenix.rebirth(context);
                  }
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Reset'),
              ),
            ],
          );
        },
      ),
    );
  }

  // Method to perform the actual reset operations
  Future<void> _performReset(
    bool resetHomepageUndoneItems,
    bool resetHomepageDoneItems,
    bool resetBoughtItemPageItems,
    bool resetFullApp,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final eventBus = EventBus();
    bool shoppingItemsChanged = false;
    
    // Reset both homepage undone and done items (clear all shopping items)
    if ((resetHomepageDoneItems && resetHomepageUndoneItems) || resetFullApp) {
      await prefs.setString('shopping_items', '[]');
      shoppingItemsChanged = true;
    } 
    // Reset homepage undone items (keep only done items)
    else if (resetHomepageUndoneItems) {
      final String? itemsJson = prefs.getString('shopping_items');
      if (itemsJson != null && itemsJson.isNotEmpty) {
        final List<dynamic> itemsList = jsonDecode(itemsJson);
        final List<dynamic> filteredItems = itemsList.where((item) => item['isBought'] == true).toList();
        await prefs.setString('shopping_items', jsonEncode(filteredItems));
        shoppingItemsChanged = true;
      }
    }
    // Reset homepage done items (keep only undone items)
    else if (resetHomepageDoneItems) {
      final String? itemsJson = prefs.getString('shopping_items');
      if (itemsJson != null && itemsJson.isNotEmpty) {
        final List<dynamic> itemsList = jsonDecode(itemsJson);
        final List<dynamic> filteredItems = itemsList.where((item) => item['isBought'] == false).toList();
        await prefs.setString('shopping_items', jsonEncode(filteredItems));
        shoppingItemsChanged = true;
      }
    }
    
    // Reset bought item page items
    if (resetBoughtItemPageItems || resetFullApp) {
      await _databaseHelper.clearBoughtItems();
      // Notify that bought items were reset
      eventBus.emitDataReset('bought_items');
    }
    
    // Full app reset - clear all preferences except critical ones
    if (resetFullApp) {
      // Get the theme and security settings before clearing
      final bool? isDarkMode = prefs.getBool('isDarkMode');
      final String? currencyCode = prefs.getString('currency_code');
      
      // Clear all preferences
      await prefs.clear();
      
      // Restore critical settings if needed
      if (isDarkMode != null) {
        await prefs.setBool('isDarkMode', isDarkMode);
      }
      if (currencyCode != null) {
        await prefs.setString('currency_code', currencyCode);
      }
      
      // Notify that a full reset was performed
      eventBus.emitDataReset('full_reset');
    }
    
    // If shopping items were changed, notify listeners
    if (shoppingItemsChanged) {
      eventBus.emitDataReset('shopping_items');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        title: const Text(
          'Settings',
          style: TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        children: <Widget>[
          const SizedBox(height: 8),

          // Security Settings
          Consumer<SecurityProvider>(
            builder: (context, securityProvider, child) => Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.security),
                  title: const Text('App Lock'),
                  subtitle: Text(securityProvider.isAppLockEnabled ? 'Enabled' : 'Disabled'),
                  trailing: Switch(
                    value: securityProvider.isAppLockEnabled,
                    onChanged: (value) {
                      if (value) {
                        _showSetPinDialog(context);
                      } else {
                        securityProvider.setAppLockEnabled(false);
                      }
                    },
                  ),
                ),
                if (securityProvider.isAppLockEnabled) ...[                  
                  ListTile(
                    leading: const SizedBox(width: 24),
                    title: const Text('Change PIN'),
                    onTap: () => _showSetPinDialog(context, isChange: true),
                  ),
                  FutureBuilder<bool>(
                    future: _isBiometricAvailableFuture,
                    builder: (context, snapshot) {
                      final bool isBiometricAvailable = snapshot.data ?? false;
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const ListTile(
                          leading: SizedBox(width: 24),
                          title: Text('Use Biometric'),
                          trailing: CircularProgressIndicator(),
                        );
                      }
                      return ListTile(
                        leading: const SizedBox(width: 24),
                        title: const Text('Use Biometric'),
                        subtitle: Text(isBiometricAvailable ? 'Unlock app with fingerprint' : 'Biometric authentication not available'),
                        trailing: Switch(
                          value: securityProvider.isBiometricEnabled && isBiometricAvailable,
                          onChanged: isBiometricAvailable
                            ? (value) async {
                                if (!value) {
                                  await securityProvider.setBiometricEnabled(false);
                                  return;
                                }
                                final authenticated = await securityProvider.authenticateWithBiometrics();
                                if (mounted) {
                                  await securityProvider.setBiometricEnabled(authenticated);
                                }
                              }
                            : null,
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),

          const Divider(),

          // App Theme
          Consumer<ThemeProvider>(
            builder: (BuildContext context, ThemeProvider themeProvider, Widget? child) => ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('App Theme'),
              subtitle: Text(themeProvider.getCurrentThemeName()),
              onTap: () {
                showDialog<void>(
                  context: context,
                  builder: (BuildContext dialogContext) => AlertDialog(
                    title: const Text('Select Theme'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        RadioListTile<ThemeMode>(
                          title: const Text('Light'),
                          value: ThemeMode.light,
                          groupValue: themeProvider.themeMode,
                          onChanged: (ThemeMode? value) {
                            if (value != null) {
                              themeProvider.setThemeMode(value);
                              Navigator.of(dialogContext).pop();
                            }
                          },
                        ),
                        RadioListTile<ThemeMode>(
                          title: const Text('Dark'),
                          value: ThemeMode.dark,
                          groupValue: themeProvider.themeMode,
                          onChanged: (ThemeMode? value) {
                            if (value != null) {
                              themeProvider.setThemeMode(value);
                              Navigator.of(dialogContext).pop();
                            }
                          },
                        ),
                        RadioListTile<ThemeMode>(
                          title: const Text('System Default'),
                          value: ThemeMode.system,
                          groupValue: themeProvider.themeMode,
                          onChanged: (ThemeMode? value) {
                            if (value != null) {
                              themeProvider.setThemeMode(value);
                              Navigator.of(dialogContext).pop();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(),

          // Currency Settings
          Consumer<CurrencyProvider>(
            builder: (BuildContext context, CurrencyProvider currencyProvider, Widget? child) => ListTile(
              leading: const Icon(Icons.currency_exchange),
              title: const Text('Currency Settings'),
              subtitle: Text('${currencyProvider.selectedCurrency.symbol} - ${currencyProvider.selectedCurrency.name}'),
              onTap: () {
                setState(() {
                  _filteredCurrencies = currencyProvider.currencies;
                });
                showDialog<void>(
                  context: context,
                  builder: (BuildContext dialogContext) => StatefulBuilder(
                    builder: (BuildContext context, StateSetter setDialogState) => AlertDialog(
                      title: const Text('Select Currency'),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: 'Search currency...',
                                prefixIcon: const Icon(Icons.search),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onChanged: (String value) {
                                setDialogState(() {
                                  _filteredCurrencies = currencyProvider.currencies
                                      .where((currency) =>
                                          currency.name.toLowerCase().contains(value.toLowerCase()) ||
                                          currency.symbol.toLowerCase().contains(value.toLowerCase()))
                                      .toList();
                                });
                              },
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: _filteredCurrencies.length,
                                itemBuilder: (BuildContext context, int index) {
                                  final currency = _filteredCurrencies[index];
                                  return RadioListTile<String>(
                                    title: Text('${currency.symbol} ${currency.name}'),
                                    value: currency.symbol,
                                    groupValue: currencyProvider.selectedCurrencySymbol,
                                    onChanged: (String? value) async {
                                      if (value != null) {
                                        await currencyProvider.setSelectedCurrency(value);
                                        if (context.mounted) {
                                          Navigator.of(dialogContext).pop();
                                        }
                                      }
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(),

          // Language Selection
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('Language Selection'),
            subtitle: Text(_selectedLanguage),
            onTap: () {
              showDialog<void>(
                context: context,
                builder: (BuildContext dialogContext) => AlertDialog(
                  title: const Text('Select Language'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      RadioListTile<String>(
                        title: const Text('English'),
                        value: 'English',
                        groupValue: _selectedLanguage,
                        onChanged: (String? value) {
                          if (value != null) {
                            setState(() {
                              _selectedLanguage = value;
                            });
                            Navigator.of(dialogContext).pop();
                          }
                        },
                      ),
                      RadioListTile<String>(
                        title: const Text('Bengali'),
                        value: 'Bengali',
                        groupValue: _selectedLanguage,
                        onChanged: (String? value) {
                          if (value != null) {
                            setState(() {
                              _selectedLanguage = value;
                            });
                            Navigator.of(dialogContext).pop();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const Divider(),

          // Reset App
          ListTile(
            leading: const Icon(Icons.restore, color: Colors.red),
            title: const Text(
              'Reset App',
              style: TextStyle(color: Colors.red),
            ),
            onTap: () {
              _showResetOptionsDialog(context);
            },
          ),
          const SizedBox(height: 16),
          const BannerAdWidget(),
        ],
      ),
    );
  }
}
