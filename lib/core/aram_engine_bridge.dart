import 'package:flutter/services.dart';

/// Typed Flutter access to the embedded Aram AI Android engine and API keys.
class AramEngineBridge {
  static const MethodChannel _channel = MethodChannel('termai/aram-engine');

  Future<Map<String, dynamic>> status() async {
    final value = await _channel.invokeMapMethod<String, dynamic>('status');
    return value ?? <String, dynamic>{};
  }

  Future<void> start() async => _channel.invokeMethod<void>('start');
  Future<void> downloadModel() async => _channel.invokeMethod<void>('downloadModel');
  Future<void> stop() async => _channel.invokeMethod<void>('stop');

  /// The returned secret is shown once; store it securely and never log it.
  Future<Map<String, dynamic>> issueOwnerKey({String name = 'مفتاح المالك'}) async {
    final value = await _channel.invokeMapMethod<String, dynamic>('issueOwnerKey', {'name': name});
    if (value == null || value['secret'] is! String) {
      throw StateError('لم يُنشأ مفتاح المالك بصورة صحيحة.');
    }
    return value;
  }

  /// Customer keys are limited by the quota selected at creation time.
  Future<Map<String, dynamic>> issueClientKey({required String name, int dailyQuota = 100}) async {
    final value = await _channel.invokeMapMethod<String, dynamic>('issueClientKey', {
      'name': name,
      'dailyQuota': dailyQuota,
    });
    if (value == null || value['secret'] is! String) {
      throw StateError('لم يُنشأ مفتاح العميل بصورة صحيحة.');
    }
    return value;
  }

  Future<List<Map<String, dynamic>>> listApiKeys() async {
    final values = await _channel.invokeListMethod<dynamic>('listApiKeys') ?? const [];
    return values.whereType<Map>().map((value) => Map<String, dynamic>.from(value)).toList();
  }

  Future<void> revokeApiKey(String id) async {
    if (id.trim().isEmpty) throw ArgumentError.value(id, 'id', 'معرف المفتاح مطلوب');
    await _channel.invokeMethod<void>('revokeApiKey', {'id': id});
  }
}
