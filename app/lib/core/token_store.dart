import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Access + refresh tokens in Android secure storage (Keystore), cached in memory.
class TokenStore {
  TokenStore([FlutterSecureStorage? storage]) : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;
  static const _access = 'habhab.access';
  static const _refresh = 'habhab.refresh';

  String? _a;
  String? _r;
  bool _loaded = false;

  Future<void> _load() async {
    if (_loaded) return;
    try {
      _a = await _s.read(key: _access);
      _r = await _s.read(key: _refresh);
    } catch (_) {
      // Keystore reset (e.g. app data restored on a new phone): start signed out.
      _a = null;
      _r = null;
    }
    _loaded = true;
  }

  Future<String?> accessToken() async {
    await _load();
    return _a;
  }

  Future<String?> refreshToken() async {
    await _load();
    return _r;
  }

  Future<void> save({required String accessToken, required String refreshToken}) async {
    _a = accessToken;
    _r = refreshToken;
    _loaded = true;
    await _s.write(key: _access, value: accessToken);
    await _s.write(key: _refresh, value: refreshToken);
  }

  Future<void> clear() async {
    _a = null;
    _r = null;
    _loaded = true;
    await _s.delete(key: _access);
    await _s.delete(key: _refresh);
  }
}
