import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/user.dart';

class AuthProvider with ChangeNotifier {
  final ApiClient _apiClient = ApiClient();
  User? _user;
  bool _isLoading = true;

  bool get isStaff => _user?.isStaff ?? false;
  bool get isAgent => _user?.isAgent ?? false;

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null;
  ApiClient get apiClient => _apiClient;
  String? get accessToken => _apiClient.accessToken;

  AuthProvider() {
    checkAuth();
  }

  Future<void> checkAuth() async {
    _isLoading = true;
    notifyListeners();
    try {
      // Check if we have access token (will trigger _loadTokens internally)
      if (_apiClient.accessToken != null) {
        final response = await _apiClient.get('/api/auth/me/');
        _user = User.fromJson(response);
      }
    } catch (e) {
      print('Auth check failed: $e');
      _user = null;
      await _apiClient.clearTokens();
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
        skipAuth: true,
      );

      print('AuthProvider: Login API success. Response keys: ${response.keys}');

      // Handle "data" wrapper if present
      final data = response['data'] ?? response;

      if (data['user'] == null) {
        print('AuthProvider Error: "user" key missing in data');
        throw Exception('Invalid response: missing user data');
      }

      print('AuthProvider: Parsing user...');
      final user = User.fromJson(data['user']);
      print(
          'AuthProvider: User parsed. Type: ${user.userType}, IsStaff: ${user.isStaff}');

      // REMOVED: Staff only check
      // if (!user.isStaff) {
      //   throw Exception('Access denied: Staff only');
      // }

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

  /// Register a new user. Returns the email address for OTP verification.
  Future<String> register({
    required String username,
    required String email,
    required String userType,
    required String password,
    required String confirmPassword,
  }) async {
    final response = await _apiClient.post(
      '/api/auth/register/',
      body: {
        'username': username,
        'email': email,
        'user_type': userType,
        'password': password,
        'confirm_password': confirmPassword,
      },
      skipAuth: true,
    );
    final data = response['data'] ?? response;
    return data['email'] as String;
  }

  /// Verify OTP and auto-login the user.
  Future<void> verifyOTP(String email, String otpCode) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiClient.post(
        '/api/auth/verify-otp/',
        body: {'email': email, 'otp_code': otpCode},
        skipAuth: true,
      );

      final data = response['data'] ?? response;
      await _apiClient.setTokens(data['access'], data['refresh']);
      _user = User.fromJson(data['user']);
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Resend OTP to the given email.
  Future<void> resendOTP(String email) async {
    await _apiClient.post(
      '/api/auth/resend-otp/',
      body: {'email': email},
      skipAuth: true,
    );
  }
}
