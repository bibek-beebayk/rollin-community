import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  // Use 10.0.2.2 for Android Emulator, localhost for Windows/iOS Simulator
  // static const String baseUrl = 'http://10.0.2.2:8000';
  static const String baseUrl = 'https://betunnel.worldstories.net';

  String? _accessToken;
  String? _refreshToken;

  ApiClient() {
    _loadTokens();
  }

  Future<void> _loadTokens() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString('access_token');
    _refreshToken = prefs.getString('refresh_token');
  }

  Future<void> setTokens(String access, String refresh) async {
    _accessToken = access;
    _refreshToken = refresh;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', access);
    await prefs.setString('refresh_token', refresh);
  }

  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
  }

  String? get accessToken => _accessToken;

  Future<Map<String, String>> _getHeaders() async {
    if (_accessToken == null) await _loadTokens();
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    return headers;
  }

  Future<dynamic> get(String endpoint) async {
    final url = '$baseUrl$endpoint';
    _logRequest('GET', url);

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: await _getHeaders(),
      );
      _logResponse('GET', url, response);
      return _handleResponse(response);
    } catch (e) {
      _logError('GET', url, e);
      rethrow;
    }
  }

  Future<dynamic> postMultipart(String endpoint, String filePath,
      {String? fieldName}) async {
    final url = '$baseUrl$endpoint';
    _logRequest('POST MULTIPART', url, body: 'File: $filePath');

    try {
      final request = http.MultipartRequest('POST', Uri.parse(url));

      // Headers
      final headers = await _getHeaders();
      // Remove Content-Type to let MultipartRequest set boundary
      headers.remove('Content-Type');
      request.headers.addAll(headers);

      // File
      request.files.add(await http.MultipartFile.fromPath(
        fieldName ?? 'file',
        filePath,
      ));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      // Token Refresh Logic (Duplicate from post - ideally refactor)
      if (response.statusCode == 401 && _refreshToken != null) {
        print('🔒 401 Unauthorized (Multipart). Attempting token refresh...');
        final success = await _refreshAccessToken();
        if (success) {
          print('🔓 Token refreshed. Retrying Multipart request...');
          final retryRequest = http.MultipartRequest('POST', Uri.parse(url));
          final newHeaders = await _getHeaders();
          newHeaders.remove('Content-Type');
          retryRequest.headers.addAll(newHeaders);
          retryRequest.files.add(await http.MultipartFile.fromPath(
            fieldName ?? 'file',
            filePath,
          ));
          final retryStreamed = await retryRequest.send();
          final retryResponse = await http.Response.fromStream(retryStreamed);
          _logResponse('POST MULTIPART', url, retryResponse);
          return _handleResponse(retryResponse);
        }
      }

      _logResponse('POST MULTIPART', url, response);
      return _handleResponse(response);
    } catch (e) {
      _logError('POST MULTIPART', url, e);
      rethrow;
    }
  }

  Future<dynamic> post(String endpoint, {dynamic body}) async {
    final url = '$baseUrl$endpoint';
    final startBody = body != null ? jsonEncode(body) : null;
    _logRequest('POST', url, body: startBody);

    try {
      var response = await http.post(
        Uri.parse(url),
        headers: await _getHeaders(),
        body: startBody,
      );

      // Token Refresh Logic
      if (response.statusCode == 401 && _refreshToken != null) {
        print('🔒 401 Unauthorized. Attempting token refresh...');
        final success = await _refreshAccessToken();
        if (success) {
          print('🔓 Token refreshed. Retrying POST request...');
          response = await http.post(
            Uri.parse(url),
            headers: await _getHeaders(),
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

  // Override GET similarly for refresh (simplified for brevity, should apply to all methods)
  // ...

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
        // Backend might cycle refresh token too
        // final newRefresh = data['refresh'] ?? _refreshToken;

        if (newAccess != null) {
          await setTokens(newAccess, _refreshToken!);
          // Note: If refresh token rotates, update it too.
          // For now assuming only access rotates or both.
          return true;
        }
      }
      return false;
    } catch (e) {
      print('Token Refresh Error: $e');
      return false;
    }
  }

  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    } else {
      throw Exception('API Error: ${response.statusCode} ${response.body}');
    }
  }

  void _logRequest(String method, String url, {String? body}) {
    print('----------------------------------------------------------------');
    print('🌐 API REQUEST: $method $url');
    if (body != null) print('📦 Body: $body');
    print('----------------------------------------------------------------');
  }

  void _logResponse(String method, String url, http.Response response) {
    print('----------------------------------------------------------------');
    print('✅ API RESPONSE: $method $url');
    print('📊 Status: ${response.statusCode}');
    print(
        '📄 Data: ${response.body.length > 500 ? "${response.body.substring(0, 500)}..." : response.body}');
    print('----------------------------------------------------------------');
  }

  void _logError(String method, String url, Object error) {
    print('----------------------------------------------------------------');
    print('❌ API ERROR: $method $url');
    print('⚠️ Details: $error');
    print('----------------------------------------------------------------');
  }
}
