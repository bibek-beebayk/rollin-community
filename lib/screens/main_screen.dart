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
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border(
            top: BorderSide(
              color: Colors.white.withValues(alpha: 0.05),
              width: 1,
            ),
          ),
        ),
        child: Consumer<ChatProvider>(
          builder: (context, chatProvider, child) {
            final int totalUnreadCount = chatProvider.activeChats
                .fold<int>(0, (sum, room) => sum + (room.unreadCount));
            final int unreadCountForBadge =
                _currentIndex == 1 ? 0 : totalUnreadCount;

            return BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) {
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
              },
              backgroundColor: Colors.transparent,
              elevation: 0,
              selectedItemColor: AppTheme.accent,
              unselectedItemColor: Colors.white.withValues(alpha: 0.4),
              showSelectedLabels: true,
              showUnselectedLabels: true,
              type: BottomNavigationBarType.fixed,
              items: [
                const BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined),
                  activeIcon: Icon(Icons.home),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: _buildChatTabIcon(
                    icon: Icons.chat_bubble_outline,
                    unreadCount: unreadCountForBadge,
                  ),
                  activeIcon: _buildChatTabIcon(
                    icon: Icons.chat_bubble,
                    unreadCount: unreadCountForBadge,
                  ),
                  label: 'Chat',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.settings_outlined),
                  activeIcon: Icon(Icons.settings),
                  label: 'Settings',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
