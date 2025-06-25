import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Currency {
  final String symbol;
  final String name;

  Currency({required this.symbol, required this.name});
}

class CurrencyProvider extends ChangeNotifier {
  SharedPreferences? _prefs;
  static const String _currencyKey = 'currency_symbol';
  String _selectedCurrencySymbol = '৳'; // Default to Taka
  
  final List<Currency> currencies = [
    Currency(symbol: '৳', name: 'Bangladeshi Taka'),
    Currency(symbol: '\$', name: 'US Dollar'),
    Currency(symbol: '₹', name: 'Indian Rupee'),
    Currency(symbol: '£', name: 'British Pound'),
    Currency(symbol: '€', name: 'Euro'),
    Currency(symbol: '¥', name: 'Japanese Yen'),
    Currency(symbol: '₩', name: 'South Korean Won'),
    Currency(symbol: '₽', name: 'Russian Ruble'),
    Currency(symbol: '﷼', name: 'Saudi Riyal'),
    Currency(symbol: '₺', name: 'Turkish Lira'),
    Currency(symbol: '₦', name: 'Nigerian Naira'),
    Currency(symbol: 'A\$', name: 'Australian Dollar'),
    Currency(symbol: 'C\$', name: 'Canadian Dollar'),
    Currency(symbol: 'R\$', name: 'Brazilian Real'),
    Currency(symbol: 'CHF', name: 'Swiss Franc'),
    Currency(symbol: 'AED', name: 'UAE Dirham'),
    Currency(symbol: 'ZAR', name: 'South African Rand'),
  ];

  CurrencyProvider(SharedPreferences prefs) {
    _prefs = prefs;
    _loadSelectedCurrency();
  }

  String get selectedCurrencySymbol => _selectedCurrencySymbol;

  Currency get selectedCurrency {
    return currencies.firstWhere(
      (currency) => currency.symbol == _selectedCurrencySymbol,
      orElse: () => currencies.first,
    );
  }

  Future<void> _loadSelectedCurrency() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedCurrencySymbol = prefs.getString(_currencyKey) ?? '৳';
    notifyListeners();
  }

  Future<void> setSelectedCurrency(String symbol) async {
    if (_selectedCurrencySymbol != symbol) {
      _selectedCurrencySymbol = symbol;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_currencyKey, symbol);
      notifyListeners();
    }
  }
}
