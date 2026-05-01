import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/social_connection.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/social_provider.dart';
import '../theme/app_theme.dart';
import '../config/app_config.dart';
import 'chat_screen.dart';
import 'player_suggestion_screen.dart';

class AgentProfileScreen extends StatefulWidget {
  final int userId;
  final bool onboardingMode;

  const AgentProfileScreen({
    super.key,
    required this.userId,
    this.onboardingMode = false,
  });

  @override
  State<AgentProfileScreen> createState() => _AgentProfileScreenState();
}

class _AgentProfileScreenState extends State<AgentProfileScreen> {
  bool _isLoading = true;
  bool _isSubmitting = false;
  User? _profile;
  int? _pendingIncomingConnectionId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    final social = context.read<SocialProvider>();
    try {
      final profile =
          await social.fetchPublicProfile(auth.apiClient, widget.userId);
      int? pendingIncomingId;
      final currentUserId = auth.user?.id;
      if (currentUserId != null) {
        final connections = await social.fetchConnections(auth.apiClient);
        pendingIncomingId = _findPendingIncomingConnectionId(
          connections,
          currentUserId: currentUserId,
          targetUserId: widget.userId,
        );
      }
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _pendingIncomingConnectionId = pendingIncomingId;
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

  int? _findPendingIncomingConnectionId(
    List<SocialConnection> connections, {
    required int currentUserId,
    required int targetUserId,
  }) {
    for (final connection in connections) {
      if (connection.status != 'pending') continue;
      if (connection.receiver.id == currentUserId &&
          connection.requester.id == targetUserId) {
        return connection.id;
      }
    }
    return null;
  }

  Future<void> _sendConnectionRequest() async {
    if (_profile == null || _isSubmitting) return;
    final auth = context.read<AuthProvider>();
    final social = context.read<SocialProvider>();
    setState(() => _isSubmitting = true);
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sending connection request...'),
          duration: Duration(seconds: 1),
        ),
      );
    }
    try {
      await social.createConnection(
        auth.apiClient,
        targetUserId: _profile!.id,
        initiatedFromOnboarding: widget.onboardingMode,
      );
      await _load();
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
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _disconnect() async {
    if (_profile == null || _isSubmitting) return;
    final auth = context.read<AuthProvider>();
    final social = context.read<SocialProvider>();
    setState(() => _isSubmitting = true);
    try {
      await social.disconnectConnection(
        auth.apiClient,
        targetUserId: _profile!.id,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Disconnected successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _acceptConnection() async {
    final connectionId = _pendingIncomingConnectionId;
    if (connectionId == null || _isSubmitting) return;
    final auth = context.read<AuthProvider>();
    final social = context.read<SocialProvider>();
    setState(() => _isSubmitting = true);
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Processing accept request...'),
          duration: Duration(seconds: 1),
        ),
      );
    }
    try {
      await social.acceptConnection(
        auth.apiClient,
        connectionId: connectionId,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connection accepted.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _rejectConnection() async {
    final connectionId = _pendingIncomingConnectionId;
    if (connectionId == null || _isSubmitting) return;
    final auth = context.read<AuthProvider>();
    final social = context.read<SocialProvider>();
    setState(() => _isSubmitting = true);
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Processing reject request...'),
          duration: Duration(seconds: 1),
        ),
      );
    }
    try {
      await social.rejectConnection(
        auth.apiClient,
        connectionId: connectionId,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connection rejected.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _chatNow() async {
    if (_profile == null || _isSubmitting) return;
    final auth = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();
    setState(() => _isSubmitting = true);
    try {
      final room = await chatProvider.startDirectAgentChat(
        auth.apiClient,
        _profile!.id,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChatScreen(room: room)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      appBar: AppBar(title: const Text('Agent Profile')),
      body: _isLoading || profile == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ProfileHero(
                    user: profile,
                    accentColor: AppTheme.primary,
                  ),
                  const SizedBox(height: 18),
                  ProfileInfoCard(
                    title: 'About this agent',
                    lines: [
                      'Joined: ${_formatJoined(profile.joinedAt)}',
                    ],
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton(
                    onPressed:
                        (!_isSubmitting && profile.canChat) ? _chatNow : null,
                    child: Text(
                      profile.canChat
                          ? 'Chat Now'
                          : 'Chat unlocks after connection',
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (profile.connectionStatus == 'pending_incoming') ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isSubmitting ? null : _rejectConnection,
                            child: const Text('Reject'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _acceptConnection,
                            child: const Text('Accept'),
                          ),
                        ),
                      ],
                    ),
                  ] else
                    OutlinedButton(
                      onPressed: _isSubmitting
                          ? null
                          : profile.canDisconnect
                              ? _disconnect
                              : profile.canConnect
                                  ? _sendConnectionRequest
                                  : null,
                      child: Text(_connectionButtonLabel(profile)),
                    ),
                  if (widget.onboardingMode) ...[
                    const SizedBox(height: 18),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => const PlayerSuggestionScreen(),
                          ),
                        );
                      },
                      child: const Text('Continue to players'),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  String _formatJoined(DateTime? value) {
    if (value == null) return 'Recently';
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }

  String _connectionButtonLabel(User profile) {
    if (profile.connectionStatus == 'connected') return 'Disconnect';
    if (profile.canDisconnect) return 'Disconnect';
    switch (profile.connectionStatus) {
      case 'pending_outgoing':
        return 'Request Sent';
      case 'pending_incoming':
        return 'Respond to Request';
      case 'connected':
        return 'Disconnect';
      default:
        return 'Connect';
    }
  }
}

class ProfileHero extends StatelessWidget {
  final User user;
  final Color accentColor;

  const ProfileHero({
    super.key,
    required this.user,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final profileImageUrl = _resolveProfileImageUrl();
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.textPrimary.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.55),
                    width: 1.5,
                  ),
                ),
                child: CircleAvatar(
                  radius: 30,
                  backgroundColor: AppTheme.cardBorder,
                  child: profileImageUrl == null
                      ? Text(
                          user.username.isNotEmpty
                              ? user.username[0].toUpperCase()
                              : 'U',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : ClipOval(
                          child: Image.network(
                            profileImageUrl,
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) {
                              return Text(
                                user.username.isNotEmpty
                                    ? user.username[0].toUpperCase()
                                    : 'U',
                                style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        user.username,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    if (user.isVerified) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.verified, color: AppTheme.accent, size: 18),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if ((user.headline ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              user.headline!.trim(),
              style: TextStyle(
                color: AppTheme.textPrimary.withValues(alpha: 0.74),
                fontSize: 13.5,
                height: 1.25,
              ),
            ),
          ] else
            const SizedBox(height: 2),
          const SizedBox(height: 8),
          Container(
            height: 1,
            width: double.infinity,
            color: AppTheme.cardBorder,
          ),
        ],
      ),
    );
  }

  String? _resolveProfileImageUrl() {
    final raw =
        (user.profileThumbnail ?? user.avatar ?? user.profilePicture)?.trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    if (raw.startsWith('/')) {
      return '${AppConfig.baseUrl}$raw';
    }
    return raw;
  }
}

class ProfileInfoCard extends StatelessWidget {
  final String title;
  final List<String> lines;

  const ProfileInfoCard({
    super.key,
    required this.title,
    required this.lines,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppTheme.textPrimary.withValues(alpha: 0.78),
              fontWeight: FontWeight.w600,
              fontSize: 13,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < lines.length; i++) ...[
            Text(
              lines[i],
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (i != lines.length - 1) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}
