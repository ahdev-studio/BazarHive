import 'dart:io';

class AdHelper {
  static String get bannerAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-2075727745408240/9452528151'; // Your Production Banner Ad ID
    } else if (Platform.isIOS) {
      return 'ca-app-pub-2075727745408240/9452528151'; // Use the same or a different ID for iOS
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }
}
