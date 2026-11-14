import 'package:flutter/services.dart';

/// Controls the app-private Ubuntu/PRoot runtime installed by Android native code.
class LinuxRuntimeService {
  static const MethodChannel _channel = MethodChannel('termai/linux');

  Future<bool> isInstalled() async =>
      await _channel.invokeMethod<bool>('isInstalled') ?? false;

  Future<Map<String, dynamic>> install() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('install');
    if (result == null || result['installed'] != true) {
      throw StateError('لم يؤكد محرك Android اكتمال تثبيت Ubuntu.');
    }
    return result;
  }
}
