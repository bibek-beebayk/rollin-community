import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../api/api_client.dart';

/// Top-level handler for background messages (must be top-level function).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('DEBUG: Background message received: ${message.messageId}');
}

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static bool _listenersBound = false;
  static String? _lastRegisteredToken;

  static Future<void> _ensureFirebaseInitialized() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  }

  /// Initialize push notifications: request permission, get token, register with backend.
  static Future<void> initialize(ApiClient apiClient) async {
    try {
      await _ensureFirebaseInitialized();

      // 1. Request permission
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('DEBUG: Push notification permission denied');
        return;
      }

      debugPrint('DEBUG: Push permission status: ${settings.authorizationStatus}');

      // 2. Get FCM token
      final token = await _messaging.getToken();
      if (token != null) {
        if (_lastRegisteredToken != token) {
          debugPrint('DEBUG: FCM Token: $token');
          await _registerToken(token, apiClient);
          _lastRegisteredToken = token;
        }
      }

      if (_listenersBound) return;
      _listenersBound = true;

      // 3. Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) {
        debugPrint('DEBUG: FCM Token refreshed: $newToken');
        _lastRegisteredToken = newToken;
        _registerToken(newToken, apiClient);
      });

      // 4. Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint(
            'DEBUG: Foreground message: ${message.notification?.title} - ${message.notification?.body}');
        // Foreground messages are already handled by the WebSocket notification channel
        // so we don't need to show a duplicate local notification.
      });

      // 5. Handle notification tap (when app was in background)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('DEBUG: Notification tapped: ${message.data}');
        // Could navigate to specific chat room here using message.data['link']
      });

      // 6. Check if app was opened from a notification (when app was terminated)
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('DEBUG: App opened from notification: ${initialMessage.data}');
      }
    } catch (e) {
      debugPrint('DEBUG: Error initializing notifications: $e');
    }
  }

  /// Register FCM token with the backend.
  static Future<void> _registerToken(
      String fcmToken, ApiClient apiClient) async {
    try {
      await apiClient.post('/api/notifications/devices/', body: {
        'fcm_token': fcmToken,
        'device':
            defaultTargetPlatform == TargetPlatform.android ? 'android' : 'ios',
        'browser': 'flutter_app',
      });
      debugPrint('DEBUG: FCM token registered with backend');
    } catch (e) {
      debugPrint('DEBUG: Error registering FCM token: $e');
    }
  }
}
