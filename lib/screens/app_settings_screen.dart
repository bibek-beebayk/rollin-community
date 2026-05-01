import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: const SafeArea(
        child: Center(
          child: Text(
            'Settings page is empty for now.',
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
        ),
      ),
    );
  }
}

