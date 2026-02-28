import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/chat_provider.dart';
import '../providers/auth_provider.dart';
import 'home_screen.dart';
import 'support_chat_tab.dart';
import 'settings_screen.dart';

class MainScreen extends StatefulWidget {
  final int initialIndex;

  const MainScreen({super.key, this.initialIndex = 0});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _chatInitialized = false;
  bool _chatTabLoaded = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    if (_currentIndex == 1) {
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
      chatProvider.setChatTabActive(_currentIndex == 1);

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
        Icon(icon),
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
                  style: const TextStyle(
                    color: Colors.white,
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
    if (index == 1 && !_chatTabLoaded) {
      _chatTabLoaded = true;
    }
    setState(() {
      _currentIndex = index;
    });
    chatProvider.setChatTabActive(index == 1);
    if (index == 0) {
      _refreshUnreadCounts();
    }
    if (index == 1) {
      // User is now in Chat tab; do not keep stale unread badge visible.
      chatProvider.clearAllUnread();
    }
  }

  Widget _buildNavItem({
    required String label,
    required IconData icon,
    required IconData activeIcon,
    required bool selected,
    required VoidCallback onTap,
    int unreadCount = 0,
  }) {
    final Color activeTextColor = Colors.white;
    final Color inactiveTextColor = Colors.white.withValues(alpha: 0.6);
    final Color iconColor = selected ? activeTextColor : inactiveTextColor;

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
                ? Colors.white.withValues(alpha: 0.08)
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
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: iconColor,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const HomeScreen(),
          _chatTabLoaded ? const SupportChatTab() : const SizedBox.shrink(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: Consumer<ChatProvider>(
        builder: (context, chatProvider, child) {
          final int totalUnreadCount = chatProvider.activeChats
              .fold<int>(0, (sum, room) => sum + room.unreadCount);
          final int unreadCountForBadge =
              _currentIndex == 1 ? 0 : totalUnreadCount;

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
                      label: 'Home',
                      icon: Icons.home_outlined,
                      activeIcon: Icons.home,
                      selected: _currentIndex == 0,
                      onTap: () => _handleNavTap(0, chatProvider),
                    ),
                    _buildNavItem(
                      label: 'Chat',
                      icon: Icons.chat_bubble_outline,
                      activeIcon: Icons.chat_bubble,
                      selected: _currentIndex == 1,
                      unreadCount: unreadCountForBadge,
                      onTap: () => _handleNavTap(1, chatProvider),
                    ),
                    _buildNavItem(
                      label: 'Settings',
                      icon: Icons.settings_outlined,
                      activeIcon: Icons.settings,
                      selected: _currentIndex == 2,
                      onTap: () => _handleNavTap(2, chatProvider),
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
