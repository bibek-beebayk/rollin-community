import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../models/room.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../screens/chat_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/main_screen.dart';
import 'navigation_service.dart';

/// Top-level handler for background messages (must be top-level function).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('DEBUG: Background message received: ${message.messageId}');
}

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static bool _listenersBound = false;
  static String? _lastRegisteredToken;
  static String? _lastHandledTapKey;

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
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
        debugPrint('DEBUG: Notification tapped: ${message.data}');
        await _handleNotificationTap(message, apiClient);
      });

      // 6. Check if app was opened from a notification (when app was terminated)
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('DEBUG: App opened from notification: ${initialMessage.data}');
        await _handleNotificationTap(initialMessage, apiClient);
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

  static int? _extractRoomId(RemoteMessage message) {
    final data = message.data;
    final dynamic roomIdRaw = data['room_id'];
    if (roomIdRaw != null) {
      final parsed = int.tryParse(roomIdRaw.toString());
      if (parsed != null) return parsed;
    }

    final link = data['link']?.toString() ?? '';
    if (link.isNotEmpty) {
      final match = RegExp(r'/chat/(\d+)').firstMatch(link);
      if (match != null) {
        return int.tryParse(match.group(1)!);
      }
    }
    return null;
  }

  static Future<void> _handleNotificationTap(
      RemoteMessage message, ApiClient apiClient) async {
    final tapKey = message.messageId ??
        '${message.sentTime?.millisecondsSinceEpoch ?? 0}:${message.data['link'] ?? ''}:${message.data['room_id'] ?? ''}';
    if (_lastHandledTapKey == tapKey) return;
    _lastHandledTapKey = tapKey;

    // Give the app a moment to mount UI/provider tree after resume/cold start.
    await Future<void>.delayed(const Duration(milliseconds: 120));

    final navState = NavigationService.navigatorKey.currentState;
    if (navState == null) return;

    final context = NavigationService.navigatorKey.currentContext;
    if (context == null) return;
    final authProvider = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();
    if (!authProvider.isAuthenticated) return;

    final roomId = _extractRoomId(message);

    if (authProvider.isStaff) {
      try {
        await chatProvider.fetchActiveChats(authProvider.apiClient);
      } catch (_) {
        // Continue with fallback room if fetch fails.
      }

      Room? targetRoom;
      if (roomId != null) {
        final idx = chatProvider.activeChats.indexWhere((r) => r.id == roomId);
        if (idx != -1) {
          targetRoom = chatProvider.activeChats[idx];
        } else {
          targetRoom = Room(
            id: roomId,
            name: 'chat_$roomId',
            slug: '',
          );
        }
      } else if (chatProvider.activeChats.isNotEmpty) {
        targetRoom = chatProvider.activeChats.first;
      }

      navState.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
        (route) => false,
      );

      if (targetRoom != null) {
        final roomToOpen = targetRoom;
        await Future<void>.delayed(const Duration(milliseconds: 80));
        navState.push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(room: roomToOpen),
          ),
        );
      }
      return;
    }

    // Player/Agent: open chat interface directly.
    navState.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const MainScreen(initialIndex: 1),
      ),
      (route) => false,
    );
  }
}
