import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureVault {
  SecureVault._();
  static final SecureVault instance = SecureVault._();
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  Future<String> read(String key) async => await _storage.read(key: key) ?? '';
  Future<void> write(String key, String value) async {
    if (value.trim().isEmpty) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: value.trim());
    }
  }
  Future<void> delete(String key) => _storage.delete(key: key);
}
