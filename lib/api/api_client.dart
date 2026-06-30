import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

class ApiClient {
  static String get baseUrl => AppConfig.baseUrl;

  String? _accessToken;
  String? _refreshToken;

  ApiClient() {
    loadTokens();
  }

  Future<void> loadTokens() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEnv = prefs.getString('api_env');
    if (savedEnv != null && savedEnv != AppConfig.env) {
      await prefs.remove('access_token');
      await prefs.remove('refresh_token');
      await prefs.setString('api_env', AppConfig.env);
      _accessToken = null;
      _refreshToken = null;
      debugPrint(
        'ApiClient: cleared saved auth tokens after environment change '
        '($savedEnv -> ${AppConfig.env}).',
      );
      return;
    }

    if (savedEnv == null) {
      await prefs.setString('api_env', AppConfig.env);
    }

    _accessToken = prefs.getString('access_token');
    _refreshToken = prefs.getString('refresh_token');
  }

  Future<void> setTokens(String access, String refresh) async {
    _accessToken = access;
    _refreshToken = refresh;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_env', AppConfig.env);
    await prefs.setString('access_token', access);
    await prefs.setString('refresh_token', refresh);
  }

  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.setString('api_env', AppConfig.env);
  }

  String? get accessToken => _accessToken;

  Future<Map<String, String>> _getHeaders({bool skipAuth = false}) async {
    if (_accessToken == null) await loadTokens();
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_accessToken != null && !skipAuth) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    return headers;
  }

  Future<dynamic> get(String endpoint, {bool skipAuth = false}) async {
    final url = '$baseUrl$endpoint';
    _logRequest('GET', url);

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: await _getHeaders(skipAuth: skipAuth),
      );
      _logResponse('GET', url, response);
      return _handleResponse(response);
    } catch (e) {
      _logError('GET', url, e);
      rethrow;
    }
  }

  Future<dynamic> postMultipart(String endpoint, String filePath,
      {String? fieldName, bool skipAuth = false}) async {
    return postMultipartWithFields(
      endpoint,
      fields: {},
      filePaths: {fieldName ?? 'file': [filePath]},
      skipAuth: skipAuth,
    );
  }

  Future<dynamic> postMultipartWithFields(
    String endpoint, {
    required Map<String, String> fields,
    required Map<String, List<String>> filePaths,
    bool isPatch = false,
    bool skipAuth = false,
  }) async {
    final url = '$baseUrl$endpoint';
    _logRequest(isPatch ? 'PATCH MULTIPART' : 'POST MULTIPART', url,
        body: 'Fields: $fields, Files: $filePaths');

    try {
      final request =
          http.MultipartRequest(isPatch ? 'PATCH' : 'POST', Uri.parse(url));

      // Headers
      final headers = await _getHeaders(skipAuth: skipAuth);
      headers.remove('Content-Type');
      request.headers.addAll(headers);

      // Add text fields
      request.fields.addAll(fields);

      // Add files
      for (final entry in filePaths.entries) {
        final fieldName = entry.key;
        for (final path in entry.value) {
          request.files.add(await http.MultipartFile.fromPath(fieldName, path));
        }
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      // Token Refresh Logic
      if (!skipAuth && response.statusCode == 401 && _refreshToken != null) {
        debugPrint(
            '🔒 401 Unauthorized (Multipart Fields). Attempting token refresh...');
        final success = await _refreshAccessToken();
        if (success) {
          debugPrint('🔓 Token refreshed. Retrying Multipart request...');
          final retryRequest =
              http.MultipartRequest(isPatch ? 'PATCH' : 'POST', Uri.parse(url));
          final newHeaders = await _getHeaders(skipAuth: skipAuth);
          newHeaders.remove('Content-Type');
          retryRequest.headers.addAll(newHeaders);
          retryRequest.fields.addAll(fields);
          for (final entry in filePaths.entries) {
            final fieldName = entry.key;
            for (final path in entry.value) {
              retryRequest.files.add(
                  await http.MultipartFile.fromPath(fieldName, path));
            }
          }
          final retryStreamed = await retryRequest.send();
          final retryResponse = await http.Response.fromStream(retryStreamed);
          _logResponse(
              isPatch ? 'PATCH MULTIPART' : 'POST MULTIPART', url, retryResponse);
          return _handleResponse(retryResponse);
        }
      }

      _logResponse(
          isPatch ? 'PATCH MULTIPART' : 'POST MULTIPART', url, response);
      return _handleResponse(response);
    } catch (e) {
      _logError(isPatch ? 'PATCH MULTIPART' : 'POST MULTIPART', url, e);
      rethrow;
    }
  }

  Future<dynamic> post(String endpoint,
      {dynamic body, bool skipAuth = false}) async {
    final url = '$baseUrl$endpoint';
    final startBody = body != null ? jsonEncode(body) : null;
    _logRequest('POST', url, body: startBody);

    try {
      var response = await http.post(
        Uri.parse(url),
        headers: await _getHeaders(skipAuth: skipAuth),
        body: startBody,
      );

      // Token Refresh Logic - Only if NOT skipping auth
      if (!skipAuth && response.statusCode == 401 && _refreshToken != null) {
        debugPrint('🔒 401 Unauthorized. Attempting token refresh...');
        final success = await _refreshAccessToken();
        if (success) {
          debugPrint('🔓 Token refreshed. Retrying POST request...');
          response = await http.post(
            Uri.parse(url),
            headers: await _getHeaders(skipAuth: skipAuth),
            body: startBody,
          );
        }
      }

      _logResponse('POST', url, response);
      return _handleResponse(response);
    } catch (e) {
      _logError('POST', url, e);
      rethrow;
    }
  }

  Future<dynamic> patch(String endpoint,
      {dynamic body, bool skipAuth = false}) async {
    final url = '$baseUrl$endpoint';
    final startBody = body != null ? jsonEncode(body) : null;
    _logRequest('PATCH', url, body: startBody);

    try {
      var response = await http.patch(
        Uri.parse(url),
        headers: await _getHeaders(skipAuth: skipAuth),
        body: startBody,
      );

      if (!skipAuth && response.statusCode == 401 && _refreshToken != null) {
        debugPrint('401 Unauthorized. Attempting token refresh for PATCH...');
        final success = await _refreshAccessToken();
        if (success) {
          response = await http.patch(
            Uri.parse(url),
            headers: await _getHeaders(skipAuth: skipAuth),
            body: startBody,
          );
        }
      }

      _logResponse('PATCH', url, response);
      return _handleResponse(response);
    } catch (e) {
      _logError('PATCH', url, e);
      rethrow;
    }
  }

  Future<dynamic> delete(String endpoint, {bool skipAuth = false}) async {
    final url = '$baseUrl$endpoint';
    _logRequest('DELETE', url);

    try {
      var response = await http.delete(
        Uri.parse(url),
        headers: await _getHeaders(skipAuth: skipAuth),
      );

      if (!skipAuth && response.statusCode == 401 && _refreshToken != null) {
        debugPrint('401 Unauthorized. Attempting token refresh for DELETE...');
        final success = await _refreshAccessToken();
        if (success) {
          response = await http.delete(
            Uri.parse(url),
            headers: await _getHeaders(skipAuth: skipAuth),
          );
        }
      }

      if (response.statusCode == 204) {
        // Successful delete with no content.
        return null;
      }

      _logResponse('DELETE', url, response);
      return _handleResponse(response);
    } catch (e) {
      _logError('DELETE', url, e);
      rethrow;
    }
  }

  Future<bool> _refreshAccessToken() async {
    try {
      final url = '$baseUrl/api/auth/token/refresh/';
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh': _refreshToken}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newAccess = data['access'];

        if (newAccess != null) {
          await setTokens(newAccess, _refreshToken!);
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('Token Refresh Error: $e');
      return false;
    }
  }

  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final body = response.body;
      if (response.statusCode == 204 || body.trim().isEmpty) {
        return null;
      }
      try {
        return jsonDecode(body);
      } catch (_) {
        // Some successful endpoints can return non-JSON payloads.
        return body;
      }
    } else {
      String errorMessage = 'API Error: ${response.statusCode}';
      try {
        final body = jsonDecode(response.body);
        if (body is Map) {
          if (body['message'] != null) {
            errorMessage = body['message'];
          } else if (body['detail'] != null) {
            errorMessage = body['detail'];
          } else if (body['error'] != null) {
            errorMessage = body['error'];
          }
        }
      } catch (_) {
        if (response.body.isNotEmpty) {
          errorMessage = 'API Error: ${response.statusCode} ${response.body}';
        }
      }
      throw Exception(errorMessage);
    }
  }

  void _logRequest(String method, String url, {String? body}) {
    debugPrint('----------------------------------------------------------------');
    debugPrint('🌐 API REQUEST: $method $url');
    if (body != null) debugPrint('📦 Body: $body');
    debugPrint('----------------------------------------------------------------');
  }

  void _logResponse(String method, String url, http.Response response) {
    debugPrint('----------------------------------------------------------------');
    debugPrint('✅ API RESPONSE: $method $url');
    debugPrint('📊 Status: ${response.statusCode}');
    debugPrint(
        '📄 Data: ${response.body.length > 500 ? "${response.body.substring(0, 500)}..." : response.body}');
    debugPrint('----------------------------------------------------------------');
  }

  void _logError(String method, String url, Object error) {
    debugPrint('----------------------------------------------------------------');
    debugPrint('❌ API ERROR: $method $url');
    debugPrint('⚠️ Details: $error');
    debugPrint('----------------------------------------------------------------');
  }
}
