import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BiometricService {
  static const _channel = MethodChannel('smart_house/biometrics');

  Future<bool> isAvailable() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      return false;
    }
    return await _channel.invokeMethod<bool>('isAvailable') ?? false;
  }

  Future<bool> authenticate({required String reason}) async {
    if (!await isAvailable()) return false;
    return await _channel.invokeMethod<bool>(
          'authenticate',
          {'reason': reason},
        ) ??
        false;
  }
}
