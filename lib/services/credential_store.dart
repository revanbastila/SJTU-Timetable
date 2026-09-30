import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StoredCredentials {
  const StoredCredentials({required this.username, required this.password});

  final String username;
  final String password;
}

abstract class CredentialStore {
  Future<StoredCredentials?> read();
  Future<void> write(String username, String password);
  Future<void> clear();
}

class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _usernameKey = 'jaccount_username';
  static const _passwordKey = 'jaccount_password';

  final FlutterSecureStorage _storage;

  @override
  Future<StoredCredentials?> read() async {
    final username = await _storage.read(key: _usernameKey);
    final password = await _storage.read(key: _passwordKey);
    if (username == null || username.isEmpty || password == null) return null;
    return StoredCredentials(username: username, password: password);
  }

  @override
  Future<void> write(String username, String password) async {
    if (username.isEmpty || password.isEmpty) return;
    await _storage.write(key: _usernameKey, value: username);
    await _storage.write(key: _passwordKey, value: password);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _usernameKey);
    await _storage.delete(key: _passwordKey);
  }
}
