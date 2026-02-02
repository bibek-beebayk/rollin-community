import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/user.dart';

class AuthProvider with ChangeNotifier {
  final ApiClient _apiClient = ApiClient();
  User? _user;
  bool _isLoading = true;

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null;
  ApiClient get apiClient => _apiClient;

  AuthProvider() {
    checkAuth();
  }

  Future<void> checkAuth() async {
    try {
      _isLoading = true;
      notifyListeners();

      final data = await _apiClient.get('/api/auth/me/');
      _user = User.fromJson(data);
    } catch (e) {
      print('Auth check failed: $e');
      _user = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> login(String username, String password) async {
    try {
      print('AuthProvider: Attempting login for $username');
      _isLoading = true;
      notifyListeners();

      final response = await _apiClient.post(
        '/api/auth/login/',
        body: {'username': username, 'password': password},
      );

      print('AuthProvider: Login API success. Response keys: ${response.keys}');

      // Handle "data" wrapper if present
      final data = response['data'] ?? response;

      if (data['user'] == null) {
        // Fallback: sometimes user data might be in root even if data wrapper exists, or specific structure
        // But based on logs: data: {refresh: ..., access: ..., user: {...}}
        print('AuthProvider Error: "user" key missing in data');
        throw Exception('Invalid response: missing user data');
      }

      print('AuthProvider: Parsing user...');
      final user = User.fromJson(data['user']);
      print(
          'AuthProvider: User parsed. Type: ${user.userType}, IsStaff: ${user.isStaff}');

      if (!user.isStaff) {
        throw Exception('Access denied: Staff only');
      }

      print('AuthProvider: Setting tokens...');
      await _apiClient.setTokens(data['access'], data['refresh']);

      _user = user;
      print('AuthProvider: Login complete. User set.');
    } catch (e) {
      print('AuthProvider: Login error: $e');
      _user = null;
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
      print(
          'AuthProvider: Notified listeners (Loading: $_isLoading, Authenticated: $isAuthenticated)');
    }
  }

  Future<void> logout() async {
    try {
      await _apiClient.post('/api/auth/logout/');
    } catch (e) {
      print('Logout error: $e');
    } finally {
      await _apiClient.clearTokens();
      _user = null;
      notifyListeners();
    }
  }
}
