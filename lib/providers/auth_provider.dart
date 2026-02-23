import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/user.dart';

class AuthProvider with ChangeNotifier {
  final ApiClient _apiClient = ApiClient();
  User? _user;
  bool _isLoading = false; // default to false
  bool _isInitializing = true; // used for app startup

  bool get isStaff => _user?.isStaff ?? false;
  bool get isAgent => _user?.isAgent ?? false;

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isInitializing => _isInitializing;
  bool get isAuthenticated => _user != null;
  ApiClient get apiClient => _apiClient;
  String? get accessToken => _apiClient.accessToken;

  AuthProvider() {
    checkAuth();
  }

  Future<void> checkAuth() async {
    _isInitializing = true;
    notifyListeners();
    try {
      // Block initialization until native local storage completely yields tokens
      await _apiClient.loadTokens();

      if (_apiClient.accessToken != null) {
        final response = await _apiClient.get('/api/auth/me/');
        final data = response['data'] ?? response;
        final userData = data['user'] ?? data;
        _user = User.fromJson(userData);
      }
    } catch (e) {
      debugPrint('Auth check failed: $e');
      _user = null;
      // ApiClient handles background token refreshing internally. If it natively
      // bubbles an exception up here to checkAuth, both tokens are truly dead.
      await _apiClient.clearTokens();
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  Future<void> login(String username, String password) async {
    try {
      debugPrint('AuthProvider: Attempting login for $username');
      _isLoading = true;
      notifyListeners();

      final response = await _apiClient.post(
        '/api/auth/login/',
        body: {'username': username, 'password': password},
        skipAuth: true,
      );

      debugPrint(
          'AuthProvider: Login API success. Response keys: ${response.keys}');

      // Handle "data" wrapper if present
      final data = response['data'] ?? response;

      if (data['user'] == null) {
        debugPrint('AuthProvider Error: "user" key missing in data');
        throw Exception('Invalid response: missing user data');
      }

      debugPrint('AuthProvider: Parsing user...');
      final user = User.fromJson(data['user']);
      debugPrint(
          'AuthProvider: User parsed. Type: ${user.userType}, IsStaff: ${user.isStaff}');

      // REMOVED: Staff only check
      // if (!user.isStaff) {
      //   throw Exception('Access denied: Staff only');
      // }

      debugPrint('AuthProvider: Setting tokens...');
      await _apiClient.setTokens(data['access'], data['refresh']);

      _user = user;
      debugPrint('AuthProvider: Login complete. User set.');
    } catch (e) {
      debugPrint('AuthProvider: Login error: $e');
      _user = null;
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
      debugPrint(
          'AuthProvider: Notified listeners (Loading: $_isLoading, Authenticated: $isAuthenticated)');
    }
  }

  Future<void> logout() async {
    try {
      await _apiClient.post('/api/auth/logout/');
    } catch (e) {
      debugPrint('Logout error: $e');
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

  /// Initiate user verification (request OTP for Game ID link)
  Future<void> initiateVerificationRequest() async {
    await _apiClient.post('/api/auth/initiate-verification-request/');
  }

  /// Verify user ID with OTP and Game ID
  Future<void> verifyUserID(String userId, String otp) async {
    final response = await _apiClient.post(
      '/api/auth/verify-user-id/',
      body: {'user_id': userId, 'otp': otp},
    );

    final data = response['data'] ?? response;

    if (data['status'] == 'verified' && _user != null) {
      // Update local user state
      _user = User(
        id: _user!.id,
        username: _user!.username,
        email: _user!.email,
        userType: _user!.userType,
        isVerified: true,
        verificationStatus: 'approved',
        avatar: _user!.avatar,
      );
      notifyListeners();
    } else {
      throw Exception(data['message'] ?? 'Verification failed');
    }
  }

  /// Initiate Forgot Password (send OTP)
  Future<void> forgotPasswordInit(String email) async {
    await _apiClient.post(
      '/api/auth/forgot-password/initiate/',
      body: {'email': email},
      skipAuth: true,
    );
  }

  /// Verify OTP for Forgot Password
  Future<String> forgotPasswordVerify(String email, String otpCode) async {
    final response = await _apiClient.post(
      '/api/auth/forgot-password/verify-otp/',
      body: {'email': email, 'otp_code': otpCode},
      skipAuth: true,
    );
    final data = response['data'] ?? response;
    return data['reset_token'] as String;
  }

  /// Complete Forgot Password (set new password)
  Future<void> forgotPasswordConfirm(
      String resetToken, String newPassword, String confirmNewPassword) async {
    await _apiClient.post(
      '/api/auth/forgot-password/complete/',
      body: {
        'reset_token': resetToken,
        'new_password': newPassword,
        'confirm_new_password': confirmNewPassword,
      },
      skipAuth: true,
    );
  }

  /// Change Password for authenticated user
  Future<void> changePassword(
      String oldPassword, String newPassword, String confirmNewPassword) async {
    try {
      await _apiClient.post(
        '/api/auth/change-password/',
        body: {
          'old_password': oldPassword,
          'new_password': newPassword,
          'confirm_new_password': confirmNewPassword,
        },
      );
    } catch (e) {
      // The API client throws a Map if the response is JSON error.
      // E.g. {"old_password":["Current password is incorrect."]}
      if (e is Map) {
        String errorMessage = "Failed to change password";
        if (e.containsKey('old_password')) {
          errorMessage = e['old_password'][0];
        } else if (e.containsKey('new_password')) {
          errorMessage = e['new_password'][0];
        } else if (e.containsKey('confirm_new_password')) {
          errorMessage = e['confirm_new_password'][0];
        } else if (e.containsKey('error')) {
          errorMessage = e['error'];
        }
        throw Exception(errorMessage);
      }
      rethrow;
    }
  }
}
