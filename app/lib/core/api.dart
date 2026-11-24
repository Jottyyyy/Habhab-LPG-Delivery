import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'config.dart';
import 'token_store.dart';

/// A request failed. [message] is safe to show to the person using the app.
class ApiException implements Exception {
  ApiException(this.message, {this.status, this.code});

  final String message;
  final int? status;
  final String? code;

  bool get isOffline => status == null;
  bool get isAuth => status == 401;

  @override
  String toString() => message;

  static ApiException from(Object e) {
    if (e is ApiException) return e;
    if (e is DioException) {
      final res = e.response;
      if (res == null) {
        return ApiException('No internet connection. Please check your data or Wi-Fi and try again.');
      }
      final data = res.data;
      final msg = data is Map && data['error'] is String ? data['error'] as String : 'Something went wrong. Please try again.';
      final code = data is Map && data['code'] is String ? data['code'] as String : null;
      return ApiException(msg, status: res.statusCode, code: code);
    }
    return ApiException('Something went wrong. Please try again.');
  }
}

typedef Json = Map<String, dynamic>;

/// Thin wrapper over Dio: JSON in/out, bearer token, one automatic refresh on 401.
class Api {
  Api({required this.tokens, required this.onSessionEnded, String? baseUrl}) {
    BaseOptions options() => BaseOptions(
          baseUrl: baseUrl ?? AppConfig.apiBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 60),
          contentType: Headers.jsonContentType,
          responseType: ResponseType.json,
          headers: {'X-Client': 'android'},
        );
    dio = Dio(options());
    _plain = Dio(options());
    dio.interceptors.add(_AuthInterceptor(_plain, tokens, () => onSessionEnded()));
  }

  final TokenStore tokens;
  final void Function() onSessionEnded;
  late final Dio dio;
  late final Dio _plain;

  Future<Json> get(String path, {Map<String, dynamic>? query}) => _run(() => dio.get<dynamic>(path, queryParameters: query));
  Future<Json> post(String path, [Object? body]) => _run(() => dio.post<dynamic>(path, data: body ?? const <String, dynamic>{}));
  Future<Json> patch(String path, Object body) => _run(() => dio.patch<dynamic>(path, data: body));

  /// Upload a JPEG/PNG as the raw request body (GCash screenshot, QR).
  Future<Json> upload(String path, Uint8List bytes, {Map<String, dynamic>? query}) => _run(
        () => dio.post<dynamic>(
          path,
          queryParameters: query,
          data: Stream.fromIterable([bytes]),
          options: Options(
            contentType: bytes.length > 3 && bytes[0] == 0x89 ? 'image/png' : 'image/jpeg',
            headers: {Headers.contentLengthHeader: bytes.length},
            sendTimeout: const Duration(seconds: 90),
          ),
        ),
      );

  /// Download an image the API protects (screenshot, QR).
  Future<Uint8List> bytes(String path) async {
    try {
      final res = await dio.get<List<int>>(path, options: Options(responseType: ResponseType.bytes));
      return Uint8List.fromList(res.data ?? const []);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<Json> _run(Future<Response<dynamic>> Function() call) async {
    try {
      final res = await call();
      final data = res.data;
      return data is Map<String, dynamic> ? data : <String, dynamic>{};
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// Sign in / sign up without the auth interceptor.
  Future<Json> postPublic(String path, Object body) async {
    try {
      final res = await _plain.post<dynamic>(path, data: body);
      return res.data as Json;
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}

class _AuthInterceptor extends QueuedInterceptor {
  _AuthInterceptor(this._plain, this._tokens, this._onSessionEnded);

  final Dio _plain;
  final TokenStore _tokens;
  final void Function() _onSessionEnded;
  Future<bool>? _refreshing;

  static bool _isAuthPath(String path) =>
      path.startsWith('/auth/login') || path.startsWith('/auth/refresh') || path.startsWith('/auth/register');

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!_isAuthPath(options.path)) {
      final t = await _tokens.accessToken();
      if (t != null) options.headers['Authorization'] = 'Bearer $t';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final res = err.response;
    final opts = err.requestOptions;
    if (res?.statusCode != 401 || _isAuthPath(opts.path) || opts.extra['retried'] == true) {
      return handler.next(err);
    }
    bool ok;
    try {
      ok = await (_refreshing ??= _refresh().whenComplete(() => _refreshing = null));
    } catch (_) {
      // Offline while refreshing: keep the session, report the original error.
      return handler.next(err);
    }
    if (!ok) {
      _onSessionEnded();
      return handler.next(err);
    }
    try {
      opts.extra['retried'] = true;
      opts.headers['Authorization'] = 'Bearer ${await _tokens.accessToken()}';
      handler.resolve(await _plain.fetch<dynamic>(opts));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  Future<bool> _refresh() async {
    final rt = await _tokens.refreshToken();
    if (rt == null) return false;
    try {
      final res = await _plain.post<Map<String, dynamic>>('/auth/refresh', data: {'refreshToken': rt});
      final body = res.data!;
      await _tokens.save(accessToken: body['accessToken'] as String, refreshToken: body['refreshToken'] as String);
      return true;
    } on DioException catch (e) {
      if (e.response == null) throw ApiException.from(e);
      if (e.response?.statusCode == 401) await _tokens.clear();
      return false;
    }
  }
}
