import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/errors.dart';

/// HTTP client for the local shop server (Node.js + MongoDB on the LAN).
/// Keeps the server address and the session token on the device.
class ApiClient {
  ApiClient(this._prefs) : baseUrl = _prefs.getString(_kUrl) ?? defaultUrl, _token = _prefs.getString(_kToken);

  static const _kUrl = 'server_url';
  static const _kToken = 'auth_token';

  /// Android emulator reaches the host machine on 10.0.2.2.
  static const defaultUrl = 'http://192.168.1.11:3000/api';

  final SharedPreferences _prefs;
  final _http = http.Client();
  String baseUrl;
  String? _token;

  bool get hasToken => _token != null;

  static Future<ApiClient> create() async => ApiClient(await SharedPreferences.getInstance());

  Future<void> setBaseUrl(String url) async {
    var u = url.trim();
    if (!u.startsWith('http')) u = 'http://$u';
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    if (!u.endsWith('/api')) u = '$u/api';
    baseUrl = u;
    await _prefs.setString(_kUrl, u);
  }

  Future<void> setToken(String? token) async {
    _token = token;
    if (token == null) {
      await _prefs.remove(_kToken);
    } else {
      await _prefs.setString(_kToken, token);
    }
  }

  /// Checks that the server answers at [baseUrl].
  Future<bool> ping() async {
    try {
      final res = await _http.get(Uri.parse('$baseUrl/health')).timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<dynamic> get(String path, [Map<String, Object?> query = const {}]) => _send('GET', path, query: query);
  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body: body);
  Future<dynamic> put(String path, [Object? body]) => _send('PUT', path, body: body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(String method, String path, {Map<String, Object?> query = const {}, Object? body}) async {
    final q = <String, String>{
      for (final e in query.entries)
        if (e.value != null && e.value != '') e.key: e.value is DateTime ? (e.value as DateTime).toUtc().toIso8601String() : '${e.value}',
    };
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: q.isEmpty ? null : q);
    final req = http.Request(method, uri)
      ..headers['content-type'] = 'application/json'
      ..headers['accept'] = 'application/json';
    if (_token != null) req.headers['authorization'] = 'Bearer $_token';
    if (body != null) req.body = jsonEncode(body, toEncodable: _encode);

    final http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 15)));
    } on TimeoutException {
      throw const NetworkException();
    } on SocketException {
      throw const NetworkException('تعذّر الوصول إلى خادم المحل. تأكد من تشغيله ومن الاتصال بنفس الشبكة.');
    } on http.ClientException {
      throw const NetworkException();
    }

    final data = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    final message = data is Map ? data['message'] as String? : null;
    final code = data is Map ? data['code'] as String? : null;
    switch (res.statusCode) {
      case 401:
        await setToken(null);
        throw BusinessException(message ?? 'انتهت الجلسة. سجّل الدخول مرة أخرى.', code: 'unauthorized');
      case 404:
        throw NotFoundException(message ?? 'العنصر غير موجود أو تم حذفه.');
      case 422:
        throw BusinessException(message ?? 'طلب غير صالح', code: code);
      default:
        throw NetworkException(message ?? 'حدث خطأ في الخادم.');
    }
  }

  static Object? _encode(Object? v) => v is DateTime ? v.toUtc().toIso8601String() : v;
}
