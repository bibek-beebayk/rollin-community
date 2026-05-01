import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/social_connection.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/social_provider.dart';
import '../theme/app_theme.dart';
import 'agent_profile_screen.dart';
import 'chat_screen.dart';
import 'main_screen.dart';

class PlayerProfileScreen extends StatefulWidget {
  final int userId;
  final bool onboardingMode;

  const PlayerProfileScreen({
    super.key,
    required this.userId,
    this.onboardingMode = false,
  });

  @override
  State<PlayerProfileScreen> createState() => _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends State<PlayerProfileScreen> {
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
      final profile = await social.fetchPublicProfile(auth.apiClient, widget.userId);
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
      final room = await chatProvider.startDirectPlayerChat(
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

  Future<void> _finishOnboarding() async {
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

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      appBar: AppBar(title: const Text('Player Profile')),
      body: _isLoading || profile == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ProfileHero(
                    user: profile,
                    accentColor: AppTheme.secondary,
                  ),
                  const SizedBox(height: 18),
                  ProfileInfoCard(
                    title: 'About this player',
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
                      onPressed: _finishOnboarding,
                      child: const Text('Finish onboarding'),
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
