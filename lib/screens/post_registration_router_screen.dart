import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/social_provider.dart';
import 'agent_suggestion_screen.dart';
import 'dashboard_screen.dart';
import 'main_screen.dart';
import 'update_screen.dart';

class PostRegistrationRouterScreen extends StatefulWidget {
  const PostRegistrationRouterScreen({super.key});

  @override
  State<PostRegistrationRouterScreen> createState() =>
      _PostRegistrationRouterScreenState();
}

class _PostRegistrationRouterScreenState
    extends State<PostRegistrationRouterScreen> {
  Widget? _destination;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveDestination());
  }

  Future<void> _resolveDestination() async {
    final authProvider = context.read<AuthProvider>();
    final socialProvider = context.read<SocialProvider>();
    final user = authProvider.user;

    if (user == null) {
      if (mounted) setState(() => _destination = const MainScreen());
      return;
    }

    if (authProvider.needsUpdate) {
      if (mounted) setState(() => _destination = const UpdateScreen());
      return;
    }

    if (user.isStaff) {
      if (mounted) setState(() => _destination = const DashboardScreen());
      return;
    }

    if (user.isAgent) {
      if (mounted) setState(() => _destination = const MainScreen());
      return;
    }

    // Players: show onboarding only if not completed yet.
    try {
      final state = await socialProvider.fetchOnboardingState(authProvider.apiClient);
      final completed = state['has_completed_social_onboarding'] == true;
      if (completed) {
        if (mounted) setState(() => _destination = const MainScreen());
        return;
      }
    } catch (_) {
      // Fail open to main app to avoid trapping user in onboarding due to transient API issues.
      if (mounted) setState(() => _destination = const MainScreen());
      return;
    }

    if (mounted) {
      setState(() => _destination = const AgentSuggestionScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    return _destination ??
        const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
  }
}
