import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class SecurityProvider extends ChangeNotifier {
  final SharedPreferences _prefs;
  final FlutterSecureStorage _secureStorage;
  final LocalAuthentication _localAuth;

  static const String _appLockEnabledKey = 'app_lock_enabled';
  static const String _biometricEnabledKey = 'biometric_enabled';
  static const String _appPinKey = 'app_pin';

  SecurityProvider(this._prefs, this._secureStorage, this._localAuth);

  bool get isAppLockEnabled => _prefs.getBool(_appLockEnabledKey) ?? false;
  bool get isBiometricEnabled => _prefs.getBool(_biometricEnabledKey) ?? false;

  Future<bool> checkBiometricAvailable() async {
    try {
      final canAuthenticateWithBiometrics = await _localAuth.canCheckBiometrics;
      final canAuthenticate = await _localAuth.isDeviceSupported();
      return canAuthenticateWithBiometrics && canAuthenticate;
    } catch (e) {
      return false;
    }
  }

  Future<void> setAppLockEnabled(bool enabled) async {
    await _prefs.setBool(_appLockEnabledKey, enabled);
    if (!enabled) {
      await _prefs.setBool(_biometricEnabledKey, false);
      await _secureStorage.delete(key: _appPinKey);
    }
    notifyListeners();
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    if (isAppLockEnabled) {
      await _prefs.setBool(_biometricEnabledKey, enabled);
      notifyListeners();
    }
  }

  Future<void> setPin(String pin) async {
    await _secureStorage.write(key: _appPinKey, value: pin);
  }

  Future<bool> verifyPin(String pin) async {
    final storedPin = await _secureStorage.read(key: _appPinKey);
    return storedPin == pin;
  }

  Future<bool> authenticateWithBiometrics() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Please authenticate to enable biometric unlock',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
          useErrorDialogs: true,
        ),
      );
    } catch (e) {
      debugPrint('Biometric authentication error: $e');
      return false;
    }
  }
}
