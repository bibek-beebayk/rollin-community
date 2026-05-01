import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../providers/social_provider.dart';
import '../theme/app_theme.dart';
import '../config/app_config.dart';
import 'main_screen.dart';
import 'player_profile_screen.dart';
import 'agent_suggestion_screen.dart';

class PlayerSuggestionScreen extends StatefulWidget {
  const PlayerSuggestionScreen({super.key});

  @override
  State<PlayerSuggestionScreen> createState() => _PlayerSuggestionScreenState();
}

class _PlayerSuggestionScreenState extends State<PlayerSuggestionScreen> {
  bool _isLoading = true;
  List<User> _players = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    final social = context.read<SocialProvider>();
    try {
      final players = await social.fetchSuggestedPlayers(auth.apiClient);
      await social.updateOnboardingState(
        auth.apiClient,
        hasSeenPlayerSuggestions: true,
      );
      if (!mounted) return;
      setState(() {
        _players = players;
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

  Future<void> _completeOnboarding() async {
    final auth = context.read<AuthProvider>();
    await context.read<SocialProvider>().updateOnboardingState(
          auth.apiClient,
          hasCompletedSocialOnboarding: true,
        );
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainScreen()),
      (route) => false,
    );
  }

  Future<void> _openProfile(User user) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerProfileScreen(
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
                    const OnboardingHeader(
                      stepLabel: 'Step 2 of 2',
                      title: 'Meet other players',
                      subtitle:
                          'Build your circle, discover shared interests, and open the door to direct conversations.',
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: _players.isEmpty
                          ? const EmptySuggestionState(
                              message:
                                  'No player suggestions are available right now.',
                            )
                          : ListView.separated(
                              itemCount: _players.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final player = _players[index];
                                return _PlayerSuggestionCard(
                                  user: player,
                                  onViewProfile: () => _openProfile(player),
                                  onConnect: () => _connectUser(player),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _completeOnboarding,
                            child: const Text('Skip for now'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _completeOnboarding,
                            child: const Text('Finish'),
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

class _PlayerSuggestionCard extends StatelessWidget {
  final User user;
  final VoidCallback onViewProfile;
  final VoidCallback onConnect;

  const _PlayerSuggestionCard({
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
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppTheme.secondary.withValues(alpha: 0.7),
            backgroundImage:
                profileImageUrl != null ? NetworkImage(profileImageUrl) : null,
            child: profileImageUrl == null
                ? Text(
                    user.username.isNotEmpty ? user.username[0].toUpperCase() : 'P',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
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
                  style: const TextStyle(
                    color: Colors.white,
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
