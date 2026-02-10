import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';

// Placeholder for Dashboard (we'll create this next)
import 'screens/dashboard_screen.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const StaffChatApp());
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
