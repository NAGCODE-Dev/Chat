import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class TokenStore {
  Future<String?> read();
  Future<void> write(String? token);
}

class KeyringTokenStore implements TokenStore {
  KeyringTokenStore({
    FlutterSecureStorage? storage,
    this._key = 'backend_api_token',
  }) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final String _key;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String? token) async {
    if (token == null || token.isEmpty) {
      await _storage.delete(key: _key);
    } else {
      await _storage.write(key: _key, value: token);
    }
  }
}
