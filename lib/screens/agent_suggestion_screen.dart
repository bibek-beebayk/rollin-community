import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../providers/social_provider.dart';
import '../theme/app_theme.dart';
import '../config/app_config.dart';
import 'agent_profile_screen.dart';
import 'player_suggestion_screen.dart';

class AgentSuggestionScreen extends StatefulWidget {
  const AgentSuggestionScreen({super.key});

  @override
  State<AgentSuggestionScreen> createState() => _AgentSuggestionScreenState();
}

class _AgentSuggestionScreenState extends State<AgentSuggestionScreen> {
  bool _isLoading = true;
  List<User> _agents = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    final social = context.read<SocialProvider>();
    try {
      final agents = await social.fetchSuggestedAgents(auth.apiClient);
      await social.updateOnboardingState(
        auth.apiClient,
        hasSeenAgentSuggestions: true,
      );
      if (!mounted) return;
      setState(() {
        _agents = agents;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    }
  }

  void _goNext() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const PlayerSuggestionScreen()),
    );
  }

  Future<void> _openProfile(User user) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AgentProfileScreen(
          userId: user.id,
          onboardingMode: true,
        ),
      ),
    );
  }

  Future<void> _connectUser(User user) async {
    final auth = context.read<AuthProvider>();
    final social = context.read<SocialProvider>();
    try {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sending connection request...')),
      );
      await social.createConnection(
        auth.apiClient,
        targetUserId: user.id,
        initiatedFromOnboarding: true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connection request sent.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OnboardingHeader(
                      stepLabel: 'Step 1 of 2',
                      title: 'Connect with top agents',
                      subtitle:
                          'Find trusted agents to chat with and start building your gaming network.',
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: _agents.isEmpty
                          ? EmptySuggestionState(
                              message:
                                  'No agent suggestions are available right now.',
                            )
                          : ListView.separated(
                              itemCount: _agents.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final agent = _agents[index];
                                return _SuggestionCard(
                                  user: agent,
                                  onViewProfile: () => _openProfile(agent),
                                  onConnect: () => _connectUser(agent),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _goNext,
                            child: const Text('Skip for now'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _goNext,
                            child: const Text('Continue'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class OnboardingHeader extends StatelessWidget {
  final String stepLabel;
  final String title;
  final String subtitle;

  const OnboardingHeader({
    super.key,
    required this.stepLabel,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withValues(alpha: 0.85),
            AppTheme.secondary.withValues(alpha: 0.55),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stepLabel,
            style: TextStyle(
              color: AppTheme.textPrimary.withValues(alpha: 0.72),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: TextStyle(
              color: AppTheme.textPrimary.withValues(alpha: 0.82),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final User user;
  final VoidCallback onViewProfile;
  final VoidCallback onConnect;

  const _SuggestionCard({
    required this.user,
    required this.onViewProfile,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final profileImageUrl = _resolveProfileImageUrl(user);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppTheme.primary.withValues(alpha: 0.85),
            backgroundImage:
                profileImageUrl != null ? NetworkImage(profileImageUrl) : null,
            child: profileImageUrl == null
                ? Text(
                    user.username.isNotEmpty ? user.username[0].toUpperCase() : 'U',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.username,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onViewProfile,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          minimumSize: const Size(0, 34),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Profile',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: onConnect,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          minimumSize: const Size(0, 34),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Connect',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _resolveProfileImageUrl(User user) {
    final raw =
        (user.profileThumbnail ?? user.avatar ?? user.profilePicture)?.trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    if (raw.startsWith('/')) return '${AppConfig.baseUrl}$raw';
    return raw;
  }
}

class EmptySuggestionState extends StatelessWidget {
  final String message;

  const EmptySuggestionState({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: AppTheme.textPrimary.withValues(alpha: 0.62)),
      ),
    );
  }
}
