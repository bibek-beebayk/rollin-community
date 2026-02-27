import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';
import 'services/notification_service.dart';

// Placeholder for Dashboard (we'll create this next)
import 'screens/dashboard_screen.dart';
import 'screens/main_screen.dart';
import 'screens/update_screen.dart';

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

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

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
        navigatorKey: navigatorKey,
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

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    if (authProvider.isInitializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (authProvider.needsUpdate) {
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
  }
}
