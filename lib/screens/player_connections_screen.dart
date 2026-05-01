import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/social_provider.dart';
import '../theme/app_theme.dart';
import '../config/app_config.dart';
import 'agent_profile_screen.dart';
import 'chat_screen.dart';
import 'pending_connections_screen.dart';
import 'player_profile_screen.dart';

class PlayerConnectionsScreen extends StatefulWidget {
  final VoidCallback onOpenMenu;

  const PlayerConnectionsScreen({
    super.key,
    required this.onOpenMenu,
  });

  @override
  State<PlayerConnectionsScreen> createState() => _PlayerConnectionsScreenState();
}

class _PlayerConnectionsScreenState extends State<PlayerConnectionsScreen> {
  static const int _pageSize = 10;
  bool _isLoading = true;
  String? _error;
  String _agentSearch = '';
  String _playerSearch = '';
  List<User> _agentConnected = const [];
  List<User> _agentNotConnected = const [];
  List<User> _playerConnected = const [];
  List<User> _playerNotConnected = const [];
  bool _agentConnectedHasMore = false;
  bool _agentNotConnectedHasMore = false;
  bool _playerConnectedHasMore = false;
  bool _playerNotConnectedHasMore = false;
  int _agentConnectedOffset = 0;
  int _agentNotConnectedOffset = 0;
  int _playerConnectedOffset = 0;
  int _playerNotConnectedOffset = 0;
  bool _isLoadingMoreAgentConnected = false;
  bool _isLoadingMoreAgentNotConnected = false;
  bool _isLoadingMorePlayerConnected = false;
  bool _isLoadingMorePlayerNotConnected = false;
  Timer? _agentSearchDebounce;
  Timer? _playerSearchDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadConnections());
  }

  bool get _isAgentUser =>
      (context.read<AuthProvider>().user?.isAgent ?? false);

  Future<void> _loadConnections() async {
    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();
    final currentUserId = auth.user?.id;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (currentUserId != null) {
        await chat.refreshPendingConnectionRequests(
          auth.apiClient,
          currentUserId: currentUserId,
        );
      }
      if (_isAgentUser) {
        await _loadPlayerSections(reset: true);
      } else {
        await Future.wait([
          _loadAgentSections(reset: true),
          _loadPlayerSections(reset: true),
        ]);
      }

      if (!mounted) return;
      setState(() {
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

  @override
  void dispose() {
    _agentSearchDebounce?.cancel();
    _playerSearchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _openProfile(User user) async {
    if (user.isAgent) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AgentProfileScreen(userId: user.id),
        ),
      );
      return;
    }

    if (user.isPlayer) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerProfileScreen(userId: user.id),
        ),
      );
    }
  }

  Future<void> _loadAgentSections({required bool reset}) async {
    await Future.wait([
      _loadAgentSection(connected: true, reset: reset),
      _loadAgentSection(connected: false, reset: reset),
    ]);
  }

  Future<void> _loadPlayerSections({required bool reset}) async {
    await Future.wait([
      _loadPlayerSection(connected: true, reset: reset),
      _loadPlayerSection(connected: false, reset: reset),
    ]);
  }

  Future<void> _loadAgentSection({
    required bool connected,
    required bool reset,
  }) async {
    final auth = context.read<AuthProvider>();
    final social = context.read<SocialProvider>();
    final offset = reset
        ? 0
        : (connected ? _agentConnectedOffset : _agentNotConnectedOffset);
    final page = await social.searchAgentConnectionsPaged(
      auth.apiClient,
      query: _agentSearch,
      section: connected ? 'connected' : 'not_connected',
      offset: offset,
      limit: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      if (connected) {
        _agentConnected = reset ? page.users : [..._agentConnected, ...page.users];
        _agentConnectedOffset = offset + page.users.length;
        _agentConnectedHasMore = page.hasMore;
      } else {
        _agentNotConnected =
            reset ? page.users : [..._agentNotConnected, ...page.users];
        _agentNotConnectedOffset = offset + page.users.length;
        _agentNotConnectedHasMore = page.hasMore;
      }
    });
  }

  Future<void> _loadPlayerSection({
    required bool connected,
    required bool reset,
  }) async {
    final auth = context.read<AuthProvider>();
    final social = context.read<SocialProvider>();
    final offset = reset
        ? 0
        : (connected ? _playerConnectedOffset : _playerNotConnectedOffset);
    final page = await social.searchPlayerConnectionsPaged(
      auth.apiClient,
      query: _playerSearch,
      section: connected ? 'connected' : 'not_connected',
      offset: offset,
      limit: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      if (connected) {
        _playerConnected =
            reset ? page.users : [..._playerConnected, ...page.users];
        _playerConnectedOffset = offset + page.users.length;
        _playerConnectedHasMore = page.hasMore;
      } else {
        _playerNotConnected =
            reset ? page.users : [..._playerNotConnected, ...page.users];
        _playerNotConnectedOffset = offset + page.users.length;
        _playerNotConnectedHasMore = page.hasMore;
      }
    });
  }

  Future<void> _openPendingConnections() async {
    await Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => const PendingConnectionsScreen(),
      ),
    )
        .then((_) => _loadConnections());
  }

  Future<void> _connectUser(User user) async {
    final auth = context.read<AuthProvider>();
    final social = context.read<SocialProvider>();
    try {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sending connection request...')),
      );
      await social.createConnection(auth.apiClient, targetUserId: user.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connection request sent.')),
      );
      await _loadConnections();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    }
  }

  Future<void> _disconnectUser(User user) async {
    final shouldDisconnect = await _confirmDisconnect(user);
    if (shouldDisconnect != true) return;

    final auth = context.read<AuthProvider>();
    final social = context.read<SocialProvider>();
    try {
      await social.disconnectConnection(auth.apiClient, targetUserId: user.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Disconnected successfully.')),
      );
      await _loadConnections();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    }
  }

  Future<bool?> _confirmDisconnect(User user) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect'),
        content: Text(
          'Are you sure you want to disconnect from ${_capitalizeUsername(user.username)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
  }

  Future<void> _chatWithUser(User user) async {
    final auth = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();
    try {
      final room = user.isAgent
          ? await chatProvider.startDirectAgentChat(auth.apiClient, user.id)
          : await chatProvider.startDirectPlayerChat(auth.apiClient, user.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChatScreen(room: room)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    }
  }

  Future<void> _handleMenuAction(User user, String action) async {
    switch (action) {
      case 'view_profile':
        await _openProfile(user);
        break;
      case 'connect':
        await _connectUser(user);
        break;
      case 'chat':
        await _chatWithUser(user);
        break;
      case 'disconnect':
        await _disconnectUser(user);
        break;
    }
  }

  bool _isConnected(User user) {
    return user.connectionStatus == 'connected' || user.canDisconnect;
  }

  String _capitalizeUsername(String input) {
    if (input.isEmpty) return input;
    final trimmed = input.trim();
    if (trimmed.isEmpty) return input;
    return trimmed[0].toUpperCase() + trimmed.substring(1);
  }

  String? _resolveProfileImageUrl(User user) {
    final raw =
        (user.profileThumbnail ?? user.avatar ?? user.profilePicture)?.trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    if (raw.startsWith('/')) return '${AppConfig.baseUrl}$raw';
    return raw;
  }

  Widget _buildConnectionTile(User user) {
    final profileImageUrl = _resolveProfileImageUrl(user);
    final connected = _isConnected(user);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: user.isAgent
              ? AppTheme.primary.withValues(alpha: 0.75)
              : AppTheme.secondary.withValues(alpha: 0.75),
          backgroundImage:
              profileImageUrl != null ? NetworkImage(profileImageUrl) : null,
          child: profileImageUrl == null
              ? Text(
                  user.username.isNotEmpty ? user.username[0].toUpperCase() : 'U',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : null,
        ),
        title: Text(
          _capitalizeUsername(user.username),
          style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700),
        ),
        trailing: PopupMenuButton<String>(
          icon: Icon(
            Icons.more_vert,
            color: AppTheme.textPrimary.withValues(alpha: 0.78),
          ),
          onSelected: (value) => _handleMenuAction(user, value),
          itemBuilder: (context) {
            if (connected) {
              return const [
                PopupMenuItem<String>(
                  value: 'view_profile',
                  child: Text('View Profile'),
                ),
                PopupMenuItem<String>(
                  value: 'chat',
                  child: Text('Chat'),
                ),
                PopupMenuItem<String>(
                  value: 'disconnect',
                  child: Text('Disconnect'),
                ),
              ];
            }
            return const [
              PopupMenuItem<String>(
                value: 'connect',
                child: Text('Connect'),
              ),
              PopupMenuItem<String>(
                value: 'view_profile',
                child: Text('View Profile'),
              ),
            ];
          },
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<User> users,
    required bool hasMore,
    required bool isLoadingMore,
    required VoidCallback onShowMore,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          if (users.isEmpty)
            Text(
              'No users found.',
              style: TextStyle(
                color: AppTheme.textSecondary.withValues(alpha: 0.9),
              ),
            )
          else
            ...users.map(_buildConnectionTile),
          if (hasMore)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: isLoadingMore ? null : onShowMore,
                child: Text(isLoadingMore ? 'Loading...' : 'Show More'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTabContent({
    required String emptyMessage,
    required String searchText,
    required ValueChanged<String> onSearchChanged,
    required String searchHint,
    required List<User> connectedUsers,
    required List<User> notConnectedUsers,
    required bool connectedHasMore,
    required bool notConnectedHasMore,
    required bool isLoadingMoreConnected,
    required bool isLoadingMoreNotConnected,
    required VoidCallback onShowMoreConnected,
    required VoidCallback onShowMoreNotConnected,
    required Future<void> Function() onRefresh,
  }) {
    final hasAny = connectedUsers.isNotEmpty || notConnectedUsers.isNotEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: TextField(
            onChanged: onSearchChanged,
            style: TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: searchHint,
              hintStyle: TextStyle(
                color: AppTheme.textSecondary.withValues(alpha: 0.85),
              ),
              filled: true,
              fillColor: AppTheme.surface.withValues(alpha: 0.72),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              prefixIcon: Icon(Icons.search, color: AppTheme.textSecondary, size: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.cardBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.cardBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.accent),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: !hasAny
                ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.surface.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.cardBorder,
                        ),
                      ),
                      child: Text(
                        searchText.isEmpty
                            ? emptyMessage
                            : 'No users match "$searchText".',
                        style: TextStyle(
                          color: AppTheme.textSecondary.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ],
                )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: 2,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _buildSection(
                          title: 'Connected',
                          users: connectedUsers,
                          hasMore: connectedHasMore,
                          isLoadingMore: isLoadingMoreConnected,
                          onShowMore: onShowMoreConnected,
                        );
                      }
                      return _buildSection(
                        title: 'Not Connected',
                        users: notConnectedUsers,
                        hasMore: notConnectedHasMore,
                        isLoadingMore: isLoadingMoreNotConnected,
                        onShowMore: onShowMoreNotConnected,
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final authUser = context.watch<AuthProvider>().user;
    final menuAvatarUrl =
        authUser != null ? _resolveProfileImageUrl(authUser) : null;
    final menuInitial = (authUser?.username.isNotEmpty ?? false)
        ? authUser!.username[0].toUpperCase()
        : 'U';
    final accentColor = Theme.of(context).colorScheme.primary;
    final isAgentUser = _isAgentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Connections'),
        actions: [
          Consumer<ChatProvider>(
            builder: (context, chatProvider, _) {
              final count = chatProvider.pendingConnectionRequests;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      tooltip: 'Pending Connections',
                      onPressed: _openPendingConnections,
                      icon: const Icon(Icons.schedule_outlined),
                    ),
                    if (count > 0)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            count > 99 ? '99+' : '$count',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Menu',
            onPressed: widget.onOpenMenu,
            icon: CircleAvatar(
              radius: 14,
              backgroundColor: accentColor.withValues(alpha: 0.95),
              child: CircleAvatar(
                radius: 12.6,
                backgroundColor: AppTheme.surface.withValues(alpha: 0.92),
                backgroundImage:
                    menuAvatarUrl != null ? NetworkImage(menuAvatarUrl) : null,
                child: menuAvatarUrl == null
                    ? Text(
                        menuInitial,
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      backgroundColor: AppTheme.background,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: Colors.red.withValues(alpha: 0.45)),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(color: AppTheme.textPrimary),
                    ),
                  ),
                )
              : isAgentUser
                  ? Column(
                      children: [
                        Expanded(
                          child: _buildTabContent(
                            emptyMessage: 'No player connections yet.',
                            searchText: _playerSearch,
                            searchHint: 'Search players',
                            connectedUsers: _playerConnected,
                            notConnectedUsers: _playerNotConnected,
                            connectedHasMore: _playerConnectedHasMore,
                            notConnectedHasMore: _playerNotConnectedHasMore,
                            isLoadingMoreConnected:
                                _isLoadingMorePlayerConnected,
                            isLoadingMoreNotConnected:
                                _isLoadingMorePlayerNotConnected,
                            onShowMoreConnected: () async {
                              if (_isLoadingMorePlayerConnected) return;
                              setState(
                                () => _isLoadingMorePlayerConnected = true,
                              );
                              try {
                                await _loadPlayerSection(
                                  connected: true,
                                  reset: false,
                                );
                              } finally {
                                if (mounted) {
                                  setState(
                                    () => _isLoadingMorePlayerConnected = false,
                                  );
                                }
                              }
                            },
                            onShowMoreNotConnected: () async {
                              if (_isLoadingMorePlayerNotConnected) return;
                              setState(
                                () => _isLoadingMorePlayerNotConnected = true,
                              );
                              try {
                                await _loadPlayerSection(
                                  connected: false,
                                  reset: false,
                                );
                              } finally {
                                if (mounted) {
                                  setState(
                                    () =>
                                        _isLoadingMorePlayerNotConnected = false,
                                  );
                                }
                              }
                            },
                            onRefresh: _loadConnections,
                            onSearchChanged: (value) {
                              setState(() => _playerSearch = value);
                              _playerSearchDebounce?.cancel();
                              _playerSearchDebounce =
                                  Timer(const Duration(milliseconds: 280), () async {
                                try {
                                  await _loadPlayerSections(reset: true);
                                } catch (_) {
                                  // Ignore transient search errors and preserve current list.
                                }
                              });
                            },
                          ),
                        ),
                      ],
                    )
                  : DefaultTabController(
                      length: 2,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppTheme.surface.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppTheme.cardBorder,
                                ),
                              ),
                              child: TabBar(
                                indicatorSize: TabBarIndicatorSize.tab,
                                indicator: BoxDecoration(
                                  color: AppTheme.accent.withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                labelColor: AppTheme.textPrimary,
                                unselectedLabelColor:
                                    AppTheme.textSecondary,
                                tabs: [
                                  Tab(
                                    text:
                                        'Agents (${_agentConnected.length + _agentNotConnected.length})',
                                  ),
                                  Tab(
                                    text:
                                        'Players (${_playerConnected.length + _playerNotConnected.length})',
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                _buildTabContent(
                                  emptyMessage: 'No agent connections yet.',
                                  searchText: _agentSearch,
                                  searchHint: 'Search agents',
                                  connectedUsers: _agentConnected,
                                  notConnectedUsers: _agentNotConnected,
                                  connectedHasMore: _agentConnectedHasMore,
                                  notConnectedHasMore: _agentNotConnectedHasMore,
                                  isLoadingMoreConnected:
                                      _isLoadingMoreAgentConnected,
                                  isLoadingMoreNotConnected:
                                      _isLoadingMoreAgentNotConnected,
                                  onShowMoreConnected: () async {
                                    if (_isLoadingMoreAgentConnected) return;
                                    setState(
                                      () => _isLoadingMoreAgentConnected = true,
                                    );
                                    try {
                                      await _loadAgentSection(
                                        connected: true,
                                        reset: false,
                                      );
                                    } finally {
                                      if (mounted) {
                                        setState(
                                          () =>
                                              _isLoadingMoreAgentConnected = false,
                                        );
                                      }
                                    }
                                  },
                                  onShowMoreNotConnected: () async {
                                    if (_isLoadingMoreAgentNotConnected) return;
                                    setState(
                                      () => _isLoadingMoreAgentNotConnected = true,
                                    );
                                    try {
                                      await _loadAgentSection(
                                        connected: false,
                                        reset: false,
                                      );
                                    } finally {
                                      if (mounted) {
                                        setState(
                                          () => _isLoadingMoreAgentNotConnected = false,
                                        );
                                      }
                                    }
                                  },
                                  onRefresh: _loadConnections,
                                  onSearchChanged: (value) {
                                    setState(() => _agentSearch = value);
                                    _agentSearchDebounce?.cancel();
                                    _agentSearchDebounce =
                                        Timer(const Duration(milliseconds: 280), () async {
                                      try {
                                        await _loadAgentSections(reset: true);
                                      } catch (_) {
                                        // Ignore transient search errors and preserve current list.
                                      }
                                    });
                                  },
                                ),
                                _buildTabContent(
                                  emptyMessage: 'No player connections yet.',
                                  searchText: _playerSearch,
                                  searchHint: 'Search players',
                                  connectedUsers: _playerConnected,
                                  notConnectedUsers: _playerNotConnected,
                                  connectedHasMore: _playerConnectedHasMore,
                                  notConnectedHasMore: _playerNotConnectedHasMore,
                                  isLoadingMoreConnected:
                                      _isLoadingMorePlayerConnected,
                                  isLoadingMoreNotConnected:
                                      _isLoadingMorePlayerNotConnected,
                                  onShowMoreConnected: () async {
                                    if (_isLoadingMorePlayerConnected) return;
                                    setState(
                                      () => _isLoadingMorePlayerConnected = true,
                                    );
                                    try {
                                      await _loadPlayerSection(
                                        connected: true,
                                        reset: false,
                                      );
                                    } finally {
                                      if (mounted) {
                                        setState(
                                          () =>
                                              _isLoadingMorePlayerConnected = false,
                                        );
                                      }
                                    }
                                  },
                                  onShowMoreNotConnected: () async {
                                    if (_isLoadingMorePlayerNotConnected) return;
                                    setState(
                                      () => _isLoadingMorePlayerNotConnected = true,
                                    );
                                    try {
                                      await _loadPlayerSection(
                                        connected: false,
                                        reset: false,
                                      );
                                    } finally {
                                      if (mounted) {
                                        setState(
                                          () =>
                                              _isLoadingMorePlayerNotConnected = false,
                                        );
                                      }
                                    }
                                  },
                                  onRefresh: _loadConnections,
                                  onSearchChanged: (value) {
                                    setState(() => _playerSearch = value);
                                    _playerSearchDebounce?.cancel();
                                    _playerSearchDebounce =
                                        Timer(const Duration(milliseconds: 280), () async {
                                      try {
                                        await _loadPlayerSections(reset: true);
                                      } catch (_) {
                                        // Ignore transient search errors and preserve current list.
                                      }
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
    );
  }
}
