import 'dart:async';

/// Data reset event class
class DataResetEvent {
  final String type;
  
  DataResetEvent(this.type);
}

/// A simple event bus to handle app-wide events
class EventBus {
  /// Singleton instance
  static final EventBus _instance = EventBus._internal();
  
  /// Factory constructor to return the same instance
  factory EventBus() {
    return _instance;
  }
  
  /// Private constructor
  EventBus._internal();
  
  /// Stream controller for data reset events
  static final StreamController<DataResetEvent> _dataResetController = 
      StreamController<DataResetEvent>.broadcast();
  
  /// Stream for data reset events
  static Stream<DataResetEvent> on<T>() {
    if (T == DataResetEvent) {
      return _dataResetController.stream;
    } else {
      throw Exception('Unknown event type');
    }
  }
  
  /// Emit a data reset event
  void emitDataReset(String type) {
    _dataResetController.add(DataResetEvent(type));
  }
  
  /// Dispose resources
  static void dispose() {
    _dataResetController.close();
  }
}
