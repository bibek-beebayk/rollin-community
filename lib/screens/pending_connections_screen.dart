import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/social_connection.dart';
import '../models/user.dart';
import '../config/app_config.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/social_provider.dart';
import '../theme/app_theme.dart';
import 'agent_profile_screen.dart';
import 'player_profile_screen.dart';

class PendingConnectionsScreen extends StatefulWidget {
  const PendingConnectionsScreen({super.key});

  @override
  State<PendingConnectionsScreen> createState() => _PendingConnectionsScreenState();
}

class _PendingConnectionsScreenState extends State<PendingConnectionsScreen> {
  bool _isLoading = true;
  String? _error;
  bool _isUpdating = false;
  List<SocialConnection> _incoming = const [];
  List<SocialConnection> _outgoing = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    final social = context.read<SocialProvider>();
    final currentUserId = auth.user?.id;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final connections = await social.fetchConnections(auth.apiClient);
      final pending = connections.where((c) => c.status == 'pending');

      final incoming = <SocialConnection>[];
      final outgoing = <SocialConnection>[];
      for (final connection in pending) {
        if (currentUserId == null) continue;
        if (connection.receiver.id == currentUserId) {
          incoming.add(connection);
        } else if (connection.requester.id == currentUserId) {
          outgoing.add(connection);
        }
      }

      incoming.sort((a, b) {
        final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
      outgoing.sort((a, b) {
        final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });

      if (!mounted) return;
      setState(() {
        _incoming = incoming;
        _outgoing = outgoing;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _openProfile(User user) async {
    if (user.isAgent) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AgentProfileScreen(userId: user.id)),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerProfileScreen(userId: user.id)),
    );
  }

  String? _resolveProfileImageUrl(User user) {
    final raw = (user.profileThumbnail ?? user.avatar ?? user.profilePicture)?.trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final normalizedPath = raw.startsWith('/') ? raw : '/$raw';
    return '${AppConfig.baseUrl}$normalizedPath';
  }

  Future<void> _handleIncomingAction({
    required SocialConnection connection,
    required bool accept,
  }) async {
    if (_isUpdating) return;
    final auth = context.read<AuthProvider>();
    final social = context.read<SocialProvider>();
    final chat = context.read<ChatProvider>();

    setState(() => _isUpdating = true);
    try {
      if (accept) {
        await social.acceptConnection(
          auth.apiClient,
          connectionId: connection.id,
        );
      } else {
        await social.rejectConnection(
          auth.apiClient,
          connectionId: connection.id,
        );
      }

      await _load();
      final currentUserId = auth.user?.id;
      if (currentUserId != null) {
        await chat.refreshPendingConnectionRequests(
          auth.apiClient,
          currentUserId: currentUserId,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accept ? 'Connection accepted.' : 'Connection rejected.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Widget _tile(
    SocialConnection connection, {
    required String subtitle,
    required bool incoming,
  }) {
    final user = incoming ? connection.requester : connection.receiver;
    final profileImageUrl = _resolveProfileImageUrl(user);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: user.isAgent
              ? AppTheme.primary.withValues(alpha: 0.8)
              : AppTheme.secondary.withValues(alpha: 0.8),
          backgroundImage:
              profileImageUrl != null ? NetworkImage(profileImageUrl) : null,
          child: profileImageUrl == null
              ? Text(
                  user.username.isNotEmpty ? user.username[0].toUpperCase() : 'U',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : null,
        ),
        title: Text(
          user.username,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.68)),
        ),
        trailing: TextButton(
          onPressed: () => _openProfile(user),
          child: const Text('View Profile'),
        ),
      ),
    );
  }

  Widget _tabContent(
    List<SocialConnection> connections, {
    required String emptyMessage,
    required String subtitle,
    required bool incoming,
  }) {
    if (connections.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.surface.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Text(
              emptyMessage,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.62)),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: connections.length,
      itemBuilder: (context, index) {
        final connection = connections[index];
        final tile = _tile(
          connection,
          subtitle: subtitle,
          incoming: incoming,
        );
        if (!incoming) return tile;

        return Column(
          children: [
            tile,
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isUpdating
                          ? null
                          : () => _handleIncomingAction(
                                connection: connection,
                                accept: false,
                              ),
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isUpdating
                          ? null
                          : () => _handleIncomingAction(
                                connection: connection,
                                accept: true,
                              ),
                      child: const Text('Accept'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pending Connections')),
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
              )
            : _error != null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: Colors.red.withValues(alpha: 0.45)),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  )
                : DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        Container(
                          margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                          decoration: BoxDecoration(
                            color: AppTheme.surface.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: TabBar(
                            indicatorSize: TabBarIndicatorSize.tab,
                            indicator: BoxDecoration(
                              color: AppTheme.accent.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            labelColor: Colors.white,
                            unselectedLabelColor:
                                Colors.white.withValues(alpha: 0.68),
                            tabs: [
                              Tab(text: 'Incoming (${_incoming.length})'),
                              Tab(text: 'Outgoing (${_outgoing.length})'),
                            ],
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _tabContent(
                                _incoming,
                                emptyMessage: 'No incoming requests.',
                                subtitle: 'Requested to connect',
                                incoming: true,
                              ),
                              _tabContent(
                                _outgoing,
                                emptyMessage: 'No outgoing requests.',
                                subtitle: 'Awaiting response',
                                incoming: false,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
        
      ),
    );
  }
}
