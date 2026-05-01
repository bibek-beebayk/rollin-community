import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../theme/app_theme.dart';
import '../providers/chat_provider.dart';
import '../providers/auth_provider.dart';
import 'home_screen.dart';
import 'post_feed_screen.dart';
import 'support_chat_tab.dart';
import 'agent_chat_hub_tab.dart';
import 'profile_screen.dart';
import 'player_connections_screen.dart';
import 'app_settings_screen.dart';
import 'login_screen.dart';
import '../config/app_config.dart';

class MainScreen extends StatefulWidget {
  final int initialIndex;

  const MainScreen({super.key, this.initialIndex = 0});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _currentIndex = 0;
  bool _chatInitialized = false;
  bool _chatTabLoaded = false;

  int _chatTabIndex(bool hasConnectionsTab) => hasConnectionsTab ? 2 : 2;
  int _connectionsTabIndex(bool hasConnectionsTab) => hasConnectionsTab ? 3 : -1;
  int _lastTabIndex(bool hasConnectionsTab) => hasConnectionsTab ? 3 : 2;
  bool _hasConnectionsAccess(dynamic user) =>
      (user?.isPlayer ?? false) || (user?.isAgent ?? false);

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    if (_currentIndex == 2) {
      _chatTabLoaded = true;
    }
    WidgetsBinding.instance.addObserver(this);
    _initChatData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onAppResumed();
      _refreshUnreadCounts();
    }
  }

  Future<void> _onAppResumed() async {
    final authProvider = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();
    await authProvider.apiClient.loadTokens();
    final token = authProvider.apiClient.accessToken;
    if (token != null && token.isNotEmpty) {
      chatProvider.handleAppResumed(token);
    }
    final currentUser = authProvider.user;
    if (_hasConnectionsAccess(currentUser)) {
      await chatProvider.refreshPendingConnectionRequests(
        authProvider.apiClient,
        currentUserId: currentUser!.id,
      );
    }
  }

  Future<void> _initChatData() async {
    if (_chatInitialized) return;
    _chatInitialized = true;

    // Ensure tokens are loaded before trying to fetch chats/connect notifications.
    final authProvider = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();

    try {
      await authProvider.apiClient.loadTokens();
      await chatProvider.fetchActiveChats(authProvider.apiClient);
      final currentUser = authProvider.user;
      if (_hasConnectionsAccess(currentUser)) {
        await chatProvider.refreshPendingConnectionRequests(
          authProvider.apiClient,
          currentUserId: currentUser!.id,
        );
      }
      chatProvider.setChatTabActive(_currentIndex == 2);

      final token = authProvider.apiClient.accessToken;
      if (token != null && token.isNotEmpty) {
        chatProvider.connectNotifications(token);
      } else {
        debugPrint('MainScreen: access token unavailable for notification WS');
      }
    } catch (e) {
      debugPrint('MainScreen: Failed to initialize chat data: $e');
    }
  }

  Future<void> _refreshUnreadCounts() async {
    final authProvider = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();
    try {
      await chatProvider.fetchActiveChats(authProvider.apiClient);
    } catch (e) {
      debugPrint('MainScreen: Failed to refresh unread counts: $e');
    }
  }

  Widget _buildChatTabIcon({
    required IconData icon,
    required int unreadCount,
  }) {
    final showBadge = unreadCount > 0;
    final badgeText = unreadCount > 99 ? '99+' : unreadCount.toString();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, size: 20),
        if (showBadge)
          Positioned(
            right: -10,
            top: -8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  badgeText,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _handleNavTap(int index, ChatProvider chatProvider) {
    final authProvider = context.read<AuthProvider>();
    final hasConnectionsTab = _hasConnectionsAccess(authProvider.user);
    final chatIndex = _chatTabIndex(hasConnectionsTab);

    if (index == chatIndex && !_chatTabLoaded) {
      _chatTabLoaded = true;
    }
    setState(() {
      _currentIndex = index;
    });
    chatProvider.setChatTabActive(index == chatIndex);
    if (index == 0) {
      _refreshUnreadCounts();
    }
    if (index == chatIndex) {
      // User entered Chat tab: keep unread counts for other conversations.
      // Only the currently opened room should be acknowledged as read.
      final userId = context.read<AuthProvider>().user?.id;
      final roomId = chatProvider.currentRoomId;
      if (userId != null && roomId != null) {
        unawaited(
          chatProvider.fetchMessages(roomId).then((_) {
            chatProvider.acknowledgeRoomAsRead(roomId, userId);
          }),
        );
      }
    }
  }

  Widget _buildNavItem({
    required IconData icon,
    required IconData activeIcon,
    required bool selected,
    required VoidCallback onTap,
    int unreadCount = 0,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.cardBorder
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                height: 2,
                width: selected ? 18 : 0,
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              _buildChatTabIcon(
                icon: selected ? activeIcon : icon,
                unreadCount: unreadCount,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openProfile() async {
    Navigator.of(context).pop();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
  }

  Future<void> _openSettings() async {
    Navigator.of(context).pop();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AppSettingsScreen()),
    );
  }

  Future<void> _logout() async {
    final authProvider = context.read<AuthProvider>();
    Navigator.of(context).pop();
    await authProvider.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  String? _resolveProfileImageUrl(dynamic user) {
    final raw =
        (user?.profileThumbnail ?? user?.avatar ?? user?.profilePicture)
            ?.toString()
            .trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final base = AppConfig.baseUrl.endsWith('/')
        ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1)
        : AppConfig.baseUrl;
    final path = raw.startsWith('/') ? raw : '/$raw';
    return '$base$path';
  }

  Widget _buildMenuDrawer(dynamic user) {
    final username = user?.username ?? 'User';
    final profileImageUrl = _resolveProfileImageUrl(user);

    return Drawer(
      backgroundColor: AppTheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.9),
                    backgroundImage: profileImageUrl != null
                        ? NetworkImage(profileImageUrl)
                        : null,
                    child: profileImageUrl == null
                        ? Text(
                            username.isNotEmpty
                                ? username[0].toUpperCase()
                                : 'U',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      username,
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: AppTheme.textSecondary.withValues(alpha: 0.55),
            ),
            ListTile(
              leading: Icon(Icons.person_outline, color: AppTheme.textPrimary),
              title: Text('Profile', style: TextStyle(color: AppTheme.textPrimary)),
              onTap: _openProfile,
            ),
            ListTile(
              leading: Icon(Icons.settings_outlined, color: AppTheme.textPrimary),
              title: Text('Appearance', style: TextStyle(color: AppTheme.textPrimary)),
              onTap: _openSettings,
            ),
            const Spacer(),
            Divider(
              height: 1,
              color: AppTheme.textSecondary.withValues(alpha: 0.55),
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text(
                'Logout',
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700),
              ),
              onTap: _logout,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopMenuButton(dynamic user) {
    final username = user?.username ?? 'User';
    final initial = username.isNotEmpty ? username[0].toUpperCase() : 'U';
    final profileImageUrl = _resolveProfileImageUrl(user);
    final accentColor = Theme.of(context).colorScheme.primary;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 8, right: 4),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: accentColor.withValues(alpha: 0.95),
                child: CircleAvatar(
                  radius: 16.6,
                  backgroundColor: AppTheme.surface.withValues(alpha: 0.92),
                  backgroundImage: profileImageUrl != null
                      ? NetworkImage(profileImageUrl)
                      : null,
                  child: profileImageUrl == null
                      ? Text(
                          initial,
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.user;
    final hasConnectionsTab = _hasConnectionsAccess(user);
    final chatIndex = _chatTabIndex(hasConnectionsTab);
    final connectionsIndex = _connectionsTabIndex(hasConnectionsTab);
    final lastTabIndex = _lastTabIndex(hasConnectionsTab);
    final effectiveIndex = _currentIndex.clamp(0, lastTabIndex).toInt();
    final useChatHubForUser = (user?.isAgent ?? false) || (user?.isPlayer ?? false);
    final isOnConnectionsTab = hasConnectionsTab && effectiveIndex == connectionsIndex;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppTheme.background,
      endDrawer: _buildMenuDrawer(user),
      body: IndexedStack(
        index: effectiveIndex,
        children: [
          const HomeScreen(),
          const PostFeedScreen(),
          _chatTabLoaded
              ? (useChatHubForUser
                  ? const AgentChatHubTab()
                  : const SupportChatTab())
              : const SizedBox.shrink(),
          if (hasConnectionsTab)
            PlayerConnectionsScreen(
              onOpenMenu: () => _scaffoldKey.currentState?.openEndDrawer(),
            ),
        ],
      ),
      bottomNavigationBar: Consumer<ChatProvider>(
        builder: (context, chatProvider, child) {
          final int totalUnreadCount = chatProvider.activeChats
              .fold<int>(0, (sum, room) => sum + room.unreadCount);
          final int unreadCountForBadge =
              effectiveIndex == chatIndex ? 0 : totalUnreadCount;

          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.surface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    _buildNavItem(
                      icon: Icons.home_outlined,
                      activeIcon: Icons.home,
                      selected: effectiveIndex == 0,
                      onTap: () => _handleNavTap(0, chatProvider),
                    ),
                    _buildNavItem(
                      icon: Icons.article_outlined,
                      activeIcon: Icons.article,
                      selected: effectiveIndex == 1,
                      onTap: () => _handleNavTap(1, chatProvider),
                    ),
                    _buildNavItem(
                      icon: Icons.chat_bubble_outline,
                      activeIcon: Icons.chat_bubble,
                      selected: effectiveIndex == chatIndex,
                      unreadCount: unreadCountForBadge,
                      onTap: () => _handleNavTap(chatIndex, chatProvider),
                    ),
                    if (hasConnectionsTab)
                      _buildNavItem(
                        icon: Icons.people_outline,
                        activeIcon: Icons.people,
                        selected: effectiveIndex == _connectionsTabIndex(hasConnectionsTab),
                        unreadCount: chatProvider.pendingConnectionRequests,
                        onTap: () => _handleNavTap(
                          _connectionsTabIndex(hasConnectionsTab),
                          chatProvider,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
      floatingActionButton: Consumer<ChatProvider>(
        builder: (context, chatProvider, _) {
          if (isOnConnectionsTab) {
            return const SizedBox.shrink();
          }
          return _buildTopMenuButton(user);
        },
      ),
    );
  }
}
