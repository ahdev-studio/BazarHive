import 'package:flutter/foundation.dart';

class CategoryNotifier {
  // Singleton pattern to ensure only one instance of the notifier exists.
  CategoryNotifier._privateConstructor();
  static final CategoryNotifier _instance = CategoryNotifier._privateConstructor();
  static CategoryNotifier get instance => _instance;

  final List<VoidCallback> _listeners = [];

  /// Adds a listener that will be called when categories are updated.
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  /// Removes a listener.
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  /// Notifies all registered listeners of a change.
  void notify() {
    // Iterate over a copy of the list in case a listener modifies the original list during iteration.
    for (final listener in List<VoidCallback>.from(_listeners)) {
      try {
        listener();
      } catch (e) {
        debugPrint('Error in category listener: $e');
      }
    }
  }
}
