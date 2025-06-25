import 'package:flutter/foundation.dart';

/// A simple singleton notifier for item list updates.
///
/// This allows different parts of the app to listen for when the item list
/// has been modified (e.g., an item was added, updated, or deleted) and
/// react accordingly, for example, by refreshing the UI.
class ItemNotifier {
  // Singleton instance
  static final ItemNotifier _instance = ItemNotifier._internal();

  // Private constructor
  ItemNotifier._internal();

  // Factory constructor to return the singleton instance
  static ItemNotifier get instance => _instance;

  final List<VoidCallback> _listeners = [];

  /// Adds a listener to the notifier.
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  /// Removes a listener from the notifier.
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  /// Notifies all registered listeners that the item list has changed.
  void notify() {
    // Create a copy of the list to avoid issues if a listener modifies the list
    for (final listener in List<VoidCallback>.from(_listeners)) {
      try {
        listener();
      } catch (e) {
        debugPrint('Error in ItemNotifier listener: $e');
      }
    }
  }
}
