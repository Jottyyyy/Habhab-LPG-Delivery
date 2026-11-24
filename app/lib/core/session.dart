import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';
import 'token_store.dart';

/// Who is signed in, plus the API client. One instance for the whole app ([session]).
/// The router listens to it: signed out → sign-in screen; customer → customer app;
/// owner/staff → store app.
class Session extends ChangeNotifier {
  Session({TokenStore? tokens, String? baseUrl}) : tokens = tokens ?? TokenStore() {
    api = Api(tokens: this.tokens, onSessionEnded: _sessionEnded, baseUrl: baseUrl);
  }

  final TokenStore tokens;
  late final Api api;
  SharedPreferences? _prefs;

  AppUser? user;
  bool ready = false;

  /// Shown once on the sign-in screen after the server ended the session.
  String? signedOutMessage;

  static const _profileKey = 'habhab.profile';

  bool get signedIn => user != null;

  /// Open the app: use the saved profile at once (works offline), then check with the server.
  Future<void> start() async {
    _prefs = await SharedPreferences.getInstance();
    final saved = _prefs!.getString(_profileKey);
    final hasToken = await tokens.refreshToken() != null;
    if (saved != null && hasToken) {
      try {
        user = AppUser.fromJson(jsonDecode(saved) as Json);
      } catch (_) {
        user = null;
      }
    }
    ready = true;
    notifyListeners();
    if (user != null) unawaited(verify());
  }

  /// Refresh the profile from the server (role or name may have changed).
  Future<void> verify() async {
    try {
      final body = await api.get('/auth/me');
      await _setUser(AppUser.fromJson(body['user'] as Json));
    } on ApiException catch (e) {
      if (e.isAuth) await _clear('Please sign in again.');
    }
  }

  Future<void> login(String phone, String password) async {
    final body = await api.postPublic('/auth/login', {'phone': phone, 'password': password});
    await _signedIn(body);
  }

  Future<void> register(Json data) async {
    final body = await api.postPublic('/auth/register', data);
    await _signedIn(body);
  }

  Future<void> changePassword(String current, String next) async {
    final body = await api.post('/auth/password', {'current': current, 'next': next});
    if (body['user'] is Json) await _setUser(AppUser.fromJson(body['user'] as Json));
  }

  Future<void> logout() async {
    final rt = await tokens.refreshToken();
    try {
      await api.post('/auth/logout', {'refreshToken': ?rt});
    } catch (_) {
      // Offline: sign out on this phone anyway.
    }
    await _clear(null);
  }

  Future<void> _signedIn(Json body) async {
    await tokens.save(accessToken: body['accessToken'] as String, refreshToken: body['refreshToken'] as String);
    signedOutMessage = null;
    await _setUser(AppUser.fromJson(body['user'] as Json));
  }

  Future<void> _setUser(AppUser u) async {
    user = u;
    await _prefs?.setString(_profileKey, jsonEncode(u.toJson()));
    notifyListeners();
  }

  void _sessionEnded() {
    _clear('Please sign in again.');
  }

  Future<void> _clear(String? message) async {
    await tokens.clear();
    await _prefs?.remove(_profileKey);
    user = null;
    signedOutMessage = message;
    notifyListeners();
  }
}

/// The app-wide session (set up in main.dart).
final session = Session();
