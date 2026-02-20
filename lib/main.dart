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
import 'screens/home_screen.dart';
import 'widgets/global_chat_bubble.dart';
import 'utils/chat_route_observer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Register background message handler
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  runApp(const StaffChatApp());
}

class StaffChatApp extends StatelessWidget {
  const StaffChatApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static final ChatRouteObserver chatRouteObserver = ChatRouteObserver();

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
        navigatorObservers: [chatRouteObserver],
        title: 'Staff Chat',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        builder: (context, child) {
          return Stack(
            children: [
              child!,
              const GlobalChatBubble(),
            ],
          );
        },
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

    if (authProvider.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (authProvider.isAuthenticated) {
      if (authProvider.isStaff) {
        return const DashboardScreen();
      } else {
        return const HomeScreen();
      }
    }

    return const LoginScreen();
  }
}
