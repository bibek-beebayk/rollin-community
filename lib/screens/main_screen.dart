import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

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
import 'my_posts_screen.dart';
import 'announcements_screen.dart';
import 'analytics_screen.dart';
import 'staff_users_screen.dart';
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
  int _connectionsTabIndex(bool hasConnectionsTab) =>
      hasConnectionsTab ? 3 : -1;
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
      await chatProvider.fetchMessageRequests(authProvider.apiClient);
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
      await chatProvider.fetchMessageRequests(authProvider.apiClient);
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
    required String label,
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
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primary.withValues(alpha: 0.20)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: selected
                ? Border.all(color: AppTheme.primary.withValues(alpha: 0.34))
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildChatTabIcon(
                icon: selected ? activeIcon : icon,
                unreadCount: unreadCount,
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: TextStyle(
                  color:
                      selected ? AppTheme.textPrimary : AppTheme.textSecondary,
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  height: 1,
                ),
                child:
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
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

  Future<void> _openMyPosts() async {
    Navigator.of(context).pop();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MyPostsScreen()),
    );
  }

  Future<void> _openDrawerScreen(Widget screen) async {
    Navigator.of(context).pop();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  void _openChatFromDrawer() {
    Navigator.of(context).pop();
    final authProvider = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();
    final hasConnectionsTab = _hasConnectionsAccess(authProvider.user);
    final chatIndex = _chatTabIndex(hasConnectionsTab);

    if (!_chatTabLoaded) {
      _chatTabLoaded = true;
    }
    setState(() {
      _currentIndex = chatIndex;
    });
    chatProvider.setChatTabActive(true);
  }

  Future<void> _logout() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radius)),
        title: Text('Logout', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('Are you sure you want to logout?',
            style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _performLogout();
            },
            child:
                const Text('Logout', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Future<void> _performLogout() async {
    final authProvider = context.read<AuthProvider>();
    // Close drawer if open
    if (_scaffoldKey.currentState?.isEndDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
    await authProvider.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  String? _resolveProfileImageUrl(dynamic user) {
    final raw = (user?.profileThumbnail ?? user?.avatar ?? user?.profilePicture)
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
    final userType = _formatUserType(user?.userType);
    final profileImageUrl = _resolveProfileImageUrl(user);

    return Drawer(
      backgroundColor: AppTheme.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              margin: const EdgeInsets.all(14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor:
                            AppTheme.primary.withValues(alpha: 0.9),
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
                                  fontWeight: FontWeight.w800,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              username,
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              userType,
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: (user?.isStaff ?? false)
                    ? [
                        _DrawerSectionTitle('Staff'),
                        _DrawerNavTile(
                          icon: Icons.analytics_outlined,
                          label: 'Analytics',
                          onTap: () =>
                              _openDrawerScreen(const AnalyticsScreen()),
                        ),
                        _DrawerNavTile(
                          icon: Icons.campaign_outlined,
                          label: 'Announcements',
                          onTap: () =>
                              _openDrawerScreen(const AnnouncementsScreen()),
                        ),
                        _DrawerNavTile(
                          icon: Icons.help_outline,
                          label: 'FAQ',
                          onTap: () => _openDrawerScreen(const FAQScreen()),
                        ),
                        _DrawerNavTile(
                          icon: Icons.people_alt_outlined,
                          label: 'Users',
                          onTap: () =>
                              _openDrawerScreen(const StaffUsersScreen()),
                        ),
                        _DrawerNavTile(
                          icon: Icons.chat_bubble_outline,
                          label: 'Chat',
                          onTap: _openChatFromDrawer,
                        ),
                        _DrawerNavTile(
                          icon: Icons.card_giftcard_outlined,
                          label: 'Redemptions',
                          onTap: () => _openDrawerScreen(
                              const RewardRedemptionsScreen()),
                        ),
                        _DrawerNavTile(
                          icon: Icons.settings_outlined,
                          label: 'Settings',
                          onTap: _openSettings,
                        ),
                      ]
                    : [
                        _DrawerSectionTitle('Community'),
                        _DrawerNavTile(
                          icon: Icons.edit_note_outlined,
                          label: 'My Posts',
                          onTap: _openMyPosts,
                        ),
                        _DrawerNavTile(
                          icon: Icons.campaign_outlined,
                          label: 'Announcements',
                          badge: 'New',
                          onTap: () =>
                              _openDrawerScreen(const AnnouncementsScreen()),
                        ),
                        _DrawerSectionTitle('Support'),
                        _DrawerNavTile(
                          icon: Icons.help_outline,
                          label: 'FAQ',
                          onTap: () => _openDrawerScreen(const FAQScreen()),
                        ),
                        _DrawerNavTile(
                          icon: Icons.shield_outlined,
                          label: 'Guidelines',
                          onTap: () =>
                              _openDrawerScreen(const GuidelinesScreen()),
                        ),
                        _DrawerSectionTitle('Settings'),
                        _DrawerNavTile(
                          icon: Icons.palette_outlined,
                          label: 'Appearance',
                          onTap: _openSettings,
                        ),
                        _DrawerNavTile(
                          icon: Icons.person_outline,
                          label: 'Profile',
                          onTap: _openProfile,
                        ),
                      ],
              ),
            ),
            Divider(
              height: 1,
              color: AppTheme.textSecondary.withValues(alpha: 0.55),
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text(
                'Logout',
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.w700),
              ),
              onTap: _logout,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopMenuButton(dynamic user) {
    if (user?.isStaff ?? false) {
      return Material(
        color: AppTheme.primary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
          child: Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.primary.withValues(alpha: 0.32),
              ),
            ),
            child: Icon(
              Icons.menu_rounded,
              color: AppTheme.textPrimary,
              size: 24,
            ),
          ),
        ),
      );
    }

    final username = user?.username ?? 'User';
    final initial = username.isNotEmpty ? username[0].toUpperCase() : 'U';
    final profileImageUrl = _resolveProfileImageUrl(user);
    final accentColor = Theme.of(context).colorScheme.primary;

    return Material(
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
    );
  }

  Widget _buildTopBar(dynamic user) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            color: AppTheme.surface.withValues(alpha: 0.84),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.cardBorder),
            boxShadow: AppTheme.visualStyle == VisualStyle.card
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/icon.png',
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Rollin Community',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    // const SizedBox(height: 1),
                    // Text(
                    //   'Hi-Rollin players hub',
                    //   style: TextStyle(
                    //     color: AppTheme.textSecondary,
                    //     fontSize: 11,
                    //     fontWeight: FontWeight.w600,
                    //   ),
                    // ),
                  ],
                ),
              ),
              _buildTopMenuButton(user),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>(); // Watch for style changes
    final authProvider = context.watch<AuthProvider>();

    final user = authProvider.user;
    final hasConnectionsTab = _hasConnectionsAccess(user);
    final chatIndex = _chatTabIndex(hasConnectionsTab);
    final lastTabIndex = _lastTabIndex(hasConnectionsTab);
    final effectiveIndex = _currentIndex.clamp(0, lastTabIndex).toInt();
    final useChatHubForUser =
        (user?.isAgent ?? false) || (user?.isPlayer ?? false);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppTheme.background,
      endDrawer: _buildMenuDrawer(user),
      body: Container(
        decoration: AppTheme.dashboardBackground(),
        child: Column(
          children: [
            _buildTopBar(user),
            Expanded(
              child: IndexedStack(
                index: effectiveIndex,
                children: [
                  const HomeScreen(showAppBar: false),
                  const PostFeedScreen(),
                  _chatTabLoaded
                      ? (useChatHubForUser
                          ? const AgentChatHubTab()
                          : const SupportChatTab())
                      : const SizedBox.shrink(),
                  if (hasConnectionsTab)
                    PlayerConnectionsScreen(
                      onOpenMenu: () =>
                          _scaffoldKey.currentState?.openEndDrawer(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Consumer<ChatProvider>(
        builder: (context, chatProvider, child) {
          final int totalUnreadCount = chatProvider.activeChats
                  .fold<int>(0, (sum, room) => sum + room.unreadCount) +
              chatProvider.messageRequests
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
                  color: AppTheme.surface.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.cardBorder),
                  boxShadow: AppTheme.visualStyle == VisualStyle.card
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.28),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    _buildNavItem(
                      icon: Icons.home_outlined,
                      activeIcon: Icons.home,
                      label: 'Home',
                      selected: effectiveIndex == 0,
                      onTap: () => _handleNavTap(0, chatProvider),
                    ),
                    _buildNavItem(
                      icon: Icons.article_outlined,
                      activeIcon: Icons.article,
                      label: 'Posts',
                      selected: effectiveIndex == 1,
                      onTap: () => _handleNavTap(1, chatProvider),
                    ),
                    _buildNavItem(
                      icon: Icons.chat_bubble_outline,
                      activeIcon: Icons.chat_bubble,
                      label: 'Chats',
                      selected: effectiveIndex == chatIndex,
                      unreadCount: unreadCountForBadge,
                      onTap: () => _handleNavTap(chatIndex, chatProvider),
                    ),
                    if (hasConnectionsTab)
                      _buildNavItem(
                        icon: Icons.people_outline,
                        activeIcon: Icons.people,
                        label: 'People',
                        selected: effectiveIndex ==
                            _connectionsTabIndex(hasConnectionsTab),
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
    );
  }
}

String _formatUserType(dynamic value) {
  final raw = value?.toString().trim();
  if (raw == null || raw.isEmpty) return 'Member';
  return raw
      .split(RegExp(r'[_\s-]+'))
      .where((part) => part.isNotEmpty)
      .map((part) =>
          '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')
      .join(' ');
}

class _DrawerSectionTitle extends StatelessWidget {
  final String text;

  const _DrawerSectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: AppTheme.textSecondary.withValues(alpha: 0.72),
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _DrawerNavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? badge;
  final VoidCallback onTap;

  const _DrawerNavTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: AppTheme.textSecondary, size: 20),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.30),
                      ),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        color: AppTheme.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
