import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';
import 'services/notification_service.dart';
import 'services/navigation_service.dart';

// Placeholder for Dashboard (we'll create this next)
import 'screens/dashboard_screen.dart';
import 'screens/main_screen.dart';
import 'screens/update_screen.dart';

class AppDistribution {
  static const MethodChannel _channel =
      MethodChannel('com.hirollin.community/app_distribution');

  static Future<bool> shouldUseCustomUpdate() async {
    try {
      final flavor = await _channel.invokeMethod<String>('getFlavor');
      final normalized = (flavor ?? '').toLowerCase().trim();
      // Play flavor: no custom update screen.
      if (normalized == 'play') return false;
      // Direct flavor (or unknown): keep custom update behavior.
      return true;
    } catch (_) {
      // Safe fallback for non-Android/any channel failure.
      return true;
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register background message handler
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Don't block first paint on Firebase initialization.
  unawaited(_initializeFirebase());

  runApp(const StaffChatApp());
}

Future<void> _initializeFirebase() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (e) {
    debugPrint('Firebase init failed during startup: $e');
  }
}

class StaffChatApp extends StatelessWidget {
  const StaffChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(
          create: (_) => ChatProvider(),
        ), // Added this line
      ],
      child: MaterialApp(
        navigatorKey: NavigationService.navigatorKey,
        title: 'Staff Chat',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        home: const AuthWrapper(),
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  static final Future<bool> _shouldUseCustomUpdateFuture =
      AppDistribution.shouldUseCustomUpdate();

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    if (authProvider.isInitializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return FutureBuilder<bool>(
      future: _shouldUseCustomUpdateFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final useCustomUpdate = snapshot.data ?? true;
        if (useCustomUpdate && authProvider.needsUpdate) {
          return const UpdateScreen();
        }

        if (authProvider.isAuthenticated) {
          if (authProvider.isStaff) {
            return const DashboardScreen();
          } else {
            return const MainScreen();
          }
        }

        return const LoginScreen();
      },
    );
  }
}
