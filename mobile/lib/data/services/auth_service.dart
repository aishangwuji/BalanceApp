import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// System identity authentication shared by app lock and private sessions.
///
/// Business Rule:
/// 1. `biometricOnly: false` allows the OS to fall back to the device PIN,
///    matching the HarmonyOS behavior where the system dialog chooses the
///    strongest available factor.
/// 2. `persistAcrossBackgrounding` keeps the session alive while the system
///    auth sheet temporarily backgrounds the app.
class AuthService {
  AuthService({LocalAuthentication? authenticator})
      : _auth = authenticator ?? LocalAuthentication();

  final LocalAuthentication _auth;

  static bool _inProgress = false;

  static bool get isInProgress => _inProgress;

  Future<bool> authenticate(String reason) async {
    if (_inProgress) {
      return false;
    }
    bool supported = false;
    try {
      supported = await _auth.isDeviceSupported();
    } catch (error) {
      debugPrint('AuthService: isDeviceSupported failed: $error');
    }
    if (!supported) {
      return false;
    }
    _inProgress = true;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } catch (error) {
      debugPrint('AuthService: authenticate failed: $error');
      return false;
    } finally {
      _inProgress = false;
    }
  }
}
