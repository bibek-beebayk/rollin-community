import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/theme_provider.dart';

import '../models/room.dart';
import '../theme/app_theme.dart';
import '../services/notification_service.dart';
import '../services/navigation_service.dart';
import 'analytics_screen.dart';
import 'announcements_screen.dart';
import 'app_settings_screen.dart';
import 'chat_screen.dart';
import 'staff_users_screen.dart';
import '../main.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isLoading = true;
  bool _autoOpenedStationSheet = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chatProvider = context.read<ChatProvider>();
      chatProvider.setChatTabActive(false);
      chatProvider.setRouteChatOpen(false);
      _fetchData(initialLoad: true);
    });
  }

  Future<void> _fetchData(
      {bool initialLoad = false, bool showLoader = false}) async {
    try {
      if (!mounted) return;
      final chatProvider = context.read<ChatProvider>();
      final hasCachedData = chatProvider.activeChats.isNotEmpty ||
          chatProvider.supportStations.isNotEmpty;

      final shouldShowLoader = showLoader || (initialLoad && !hasCachedData);
      if (shouldShowLoader) {
        setState(() => _isLoading = true);
      } else if (_isLoading && hasCachedData) {
        setState(() => _isLoading = false);
      }

      final apiClient = context.read<AuthProvider>().apiClient;
      final authProvider = context.read<AuthProvider>();

      await Future.wait([
        chatProvider.fetchActiveChats(apiClient),
        chatProvider.fetchSupportStations(apiClient),
      ]);

      if (mounted) {
        if (_isLoading) {
          setState(() => _isLoading = false);
        }
        // Connect to notifications channel
        await authProvider.apiClient.loadTokens();
        final token = authProvider.apiClient.accessToken;
        if (token != null && token.isNotEmpty) {
          chatProvider.connectNotifications(token);
        } else {
          debugPrint(
              'DashboardScreen: access token unavailable for notification WS');
        }
        // Initialize push notifications (idempotent and now safe to call repeatedly)
        NotificationService.initialize(authProvider.apiClient);

        // If staff has no active station, immediately guide them to station selection.
        if (!_autoOpenedStationSheet &&
            !_hasConnectedStation(
                chatProvider.supportStations, authProvider.user)) {
          _autoOpenedStationSheet = true;
          Future.microtask(() {
            if (!mounted) return;
            _showStationsSheet(
              context,
              chatProvider.supportStations,
              authProvider.user,
            );
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load data: $e')),
        );
      }
    }
  }

  Future<void> _toggleStation(Room station) async {
    final chatProvider = context.read<ChatProvider>();
    final apiClient = context.read<AuthProvider>().apiClient;
    final currentUser = context.read<AuthProvider>().user;
    final isConnected = station.staff?.id == currentUser?.id;

    try {
      setState(() => _isLoading = true); // Show loading during station toggle
      if (isConnected) {
        await chatProvider.leaveStation(apiClient, station.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Disconnected from ${station.name}')),
        );
      } else {
        await chatProvider.joinStation(apiClient, station.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connected to ${station.name}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update station: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _hasConnectedStation(List<Room> stations, dynamic currentUser) {
    return stations.any((s) => s.staff?.id == currentUser?.id);
  }

  void _showStationsSheet(
      BuildContext context, List<Room> stations, dynamic currentUser) {
    // Categorize stations
    final myRooms =
        stations.where((s) => s.staff?.id == currentUser?.id).toList();
    final available = stations.where((s) => s.staff == null).toList();
    final occupied = stations
        .where((s) => s.staff != null && s.staff?.id != currentUser?.id)
        .toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (_, scrollController) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListView(
                controller: scrollController,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.cardBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    'Support Rooms',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Section 1: My Rooms
                  if (myRooms.isNotEmpty) ...[
                    _sectionHeader('My Rooms', Icons.person, AppTheme.primary),
                    ...myRooms.map((station) => _stationTile(
                          station: station,
                          trailing: _actionButton(
                            label: 'Leave',
                            color: Colors.redAccent,
                            onPressed: () {
                              Navigator.pop(ctx);
                              _toggleStation(station);
                            },
                          ),
                          textColor: AppTheme.textPrimary,
                        )),
                    const SizedBox(height: 16),
                  ],

                  // Section 2: Available Rooms
                  if (available.isNotEmpty) ...[
                    _sectionHeader(
                        'Available', Icons.meeting_room, Colors.green),
                    ...available.map((station) => _stationTile(
                          station: station,
                          trailing: _actionButton(
                            label: 'Enter',
                            color: Colors.green,
                            onPressed: () {
                              Navigator.pop(ctx);
                              _toggleStation(station);
                            },
                          ),
                          textColor: AppTheme.textPrimary,
                        )),
                    const SizedBox(height: 16),
                  ],

                  // Section 3: Occupied by Others
                  if (occupied.isNotEmpty) ...[
                    _sectionHeader('Occupied', Icons.lock,
                        AppTheme.textSecondary.withValues(alpha: 0.55)),
                    ...occupied.map((station) => _stationTile(
                          station: station,
                          subtitle:
                              'Occupied by ${station.staff?.username ?? 'unknown'}',
                          trailing: Icon(Icons.lock_outline,
                              color: AppTheme.cardBorder, size: 18),
                          textColor:
                              AppTheme.textSecondary.withValues(alpha: 0.55),
                        )),
                  ],

                  if (stations.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          'No support rooms available',
                          style: TextStyle(
                              color: AppTheme.textSecondary
                                  .withValues(alpha: 0.7)),
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _sectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stationTile({
    required Room station,
    required Widget trailing,
    required Color textColor,
    String? subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  station.name,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(
                        color: textColor.withValues(alpha: 0.6), fontSize: 12),
                  ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 32,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.15),
          foregroundColor: color,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: AppTheme.borderRadius),
          side: BorderSide(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Future<void> _openChat(Room room) async {
    context.read<ChatProvider>().clearUnread(room.id);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(room: room)),
    );
    if (!mounted) return;
    final chatProvider = context.read<ChatProvider>();
    chatProvider.setRouteChatOpen(false);
    chatProvider.setChatTabActive(false);
  }

  Future<void> _openDrawerScreen(Widget screen) async {
    Navigator.of(context).pop();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  void _openStaffChatFromDrawer() {
    Navigator.of(context).pop();
  }

  Widget _buildStaffDrawer(dynamic user) {
    final username = user?.username ?? 'Staff';
    final userType = _formatUserType(user?.userType);

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
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.24),
                    child: Icon(
                      Icons.admin_panel_settings_outlined,
                      color: AppTheme.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  const _StaffDrawerSectionTitle('Staff'),
                  _StaffDrawerNavTile(
                    icon: Icons.analytics_outlined,
                    label: 'Analytics',
                    onTap: () => _openDrawerScreen(const AnalyticsScreen()),
                  ),
                  _StaffDrawerNavTile(
                    icon: Icons.campaign_outlined,
                    label: 'Announcements',
                    onTap: () => _openDrawerScreen(const AnnouncementsScreen()),
                  ),
                  _StaffDrawerNavTile(
                    icon: Icons.help_outline,
                    label: 'FAQ',
                    onTap: () => _openDrawerScreen(const FAQScreen()),
                  ),
                  _StaffDrawerNavTile(
                    icon: Icons.people_alt_outlined,
                    label: 'Users',
                    onTap: () => _openDrawerScreen(const StaffUsersScreen()),
                  ),
                  _StaffDrawerNavTile(
                    icon: Icons.chat_bubble_outline,
                    label: 'Chat',
                    onTap: _openStaffChatFromDrawer,
                  ),
                  _StaffDrawerNavTile(
                    icon: Icons.card_giftcard_outlined,
                    label: 'Redemptions',
                    onTap: () =>
                        _openDrawerScreen(const RewardRedemptionsScreen()),
                  ),
                  _StaffDrawerNavTile(
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                    onTap: () => _openDrawerScreen(const AppSettingsScreen()),
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
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onTap: () {
                Navigator.of(context).pop();
                _showLogoutConfirmation(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final chatProvider = context.watch<ChatProvider>();
    final currentUser = context.read<AuthProvider>().user;
    final activeChats = chatProvider.activeChats; // These are my chats
    final stations = chatProvider.supportStations;
    final connectedStations =
        stations.where((s) => s.staff?.id == currentUser?.id).length;
    final unreadTotal =
        activeChats.fold<int>(0, (sum, room) => sum + room.unreadCount);
    final hasConnectedStation = _hasConnectedStation(stations, currentUser);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppTheme.background,
      endDrawer: _buildStaffDrawer(currentUser),
      appBar: AppBar(
        title: const Text('Staff Control Center'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => _fetchData(showLoader: true),
          ),
          IconButton(
            icon: const Icon(Icons.hub),
            tooltip: 'Manage Stations',
            onPressed: () => _showStationsSheet(context, stations, currentUser),
          ),
          IconButton(
            icon: const Icon(Icons.menu_rounded),
            tooltip: 'Staff Menu',
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () => _fetchData(showLoader: false),
            color: AppTheme.accent,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _buildOverviewCard(
                  connectedStations: connectedStations,
                  activeChats: activeChats.length,
                  unreadTotal: unreadTotal,
                ),
                const SizedBox(height: 16),
                _buildSectionTitle('Active Conversations', activeChats.length),
                const SizedBox(height: 10),
                if (activeChats.isEmpty)
                  _buildEmptyChatsCard(
                    hasConnectedStation: hasConnectedStation,
                    stations: stations,
                    currentUser: currentUser,
                  )
                else
                  ...activeChats.map(_buildChatCard),
              ],
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.25),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildOverviewCard({
    required int connectedStations,
    required int activeChats,
    required int unreadTotal,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: AppTheme.itemDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights, size: 14, color: AppTheme.textSecondary),
              const SizedBox(width: 6),
              Text(
                'Shift Overview',
                style: TextStyle(
                  color: AppTheme.textPrimary.withValues(alpha: 0.95),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  'Stations',
                  connectedStations.toString(),
                  Icons.hub,
                  Colors.tealAccent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  'Chats',
                  activeChats.toString(),
                  Icons.chat_bubble,
                  AppTheme.accent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  'Unread',
                  unreadTotal.toString(),
                  Icons.mark_chat_unread,
                  Colors.redAccent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile(
      String label, String value, IconData icon, Color iconColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: AppTheme.itemDecoration(hasBorder: false),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, int count) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.cardBorder,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: AppTheme.textPrimary.withValues(alpha: 0.9),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyChatsCard({
    required bool hasConnectedStation,
    required List<Room> stations,
    required dynamic currentUser,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.itemDecoration(),
      child: Column(
        children: [
          Icon(Icons.forum_outlined,
              size: 44, color: AppTheme.textSecondary.withValues(alpha: 0.35)),
          const SizedBox(height: 12),
          Text(
            hasConnectedStation
                ? 'No active chats yet'
                : 'No active station selected',
            style: TextStyle(
              color: AppTheme.textPrimary.withValues(alpha: 0.9),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasConnectedStation
                ? 'Pull to refresh while waiting for new messages.'
                : 'Connect to a station to start receiving conversations.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textSecondary.withValues(alpha: 0.75),
              fontSize: 12,
            ),
          ),
          if (!hasConnectedStation) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () =>
                  _showStationsSheet(context, stations, currentUser),
              icon: const Icon(Icons.hub),
              label: const Text('Select Station'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textPrimary,
                side: BorderSide(
                    color: AppTheme.textSecondary.withValues(alpha: 0.35)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChatCard(Room room) {
    final title = room.roomType == 'support'
        ? (room.counterpart?.username ?? _getDisplayName(room.name))
        : _getDisplayName(room.name);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.surface.withValues(alpha: 0.35)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: () => _openChat(room),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppTheme.primary,
                child: Text(
                  title.isNotEmpty ? title[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_getUserTypeLabel(room) != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: _getUserTypeColor(room),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _getUserTypeLabel(room)!,
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      room.queueName ?? 'ID: ${room.id}',
                      style: TextStyle(
                        color: AppTheme.textPrimary.withValues(alpha: 0.65),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (room.unreadCount > 0)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${room.unreadCount}',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              Icon(Icons.chevron_right,
                  color: AppTheme.textSecondary.withValues(alpha: 0.75)),
            ],
          ),
        ),
      ),
    );
  }

  String _getDisplayName(String rawName) {
    String name = rawName;
    if (name.startsWith('chat__')) {
      name = name.substring(6);
    } else if (name.startsWith('chat_')) {
      name = name.substring(5);
    }

    // Capitalize first letter
    if (name.isNotEmpty) {
      return name[0].toUpperCase() + name.substring(1);
    }
    return name;
  }

  String? _getUserTypeLabel(Room room) {
    // Infer from matching queue name or other logic
    // Assuming queues are named like "Player Support", "Agent Support"
    final q = room.queueName?.toLowerCase() ?? '';
    if (q.contains('agent')) return 'A';
    if (q.contains('player')) return 'P';
    if (q.contains('high roller')) return 'VIP';
    return null; // Or default to 'USER'
  }

  Color _getUserTypeColor(Room room) {
    final label = _getUserTypeLabel(room);
    switch (label) {
      case 'A':
        return Colors.blueAccent;
      case 'P':
        return Colors.green;
      case 'VIP':
        return Colors.amber.shade700;
      default:
        return Colors.grey;
    }
  }

  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Log Out', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          'Are you sure you want to log out?',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child:
                Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext); // Close dialog

              final authProvider = context.read<AuthProvider>();
              final chatProvider = context.read<ChatProvider>();
              final currentUser = authProvider.user;

              if (currentUser != null) {
                // Determine occupied stations and leave them
                for (var station in chatProvider.supportStations) {
                  if (station.staff?.id == currentUser.id) {
                    try {
                      await chatProvider.leaveStation(
                          authProvider.apiClient, station.id);
                    } catch (e) {
                      debugPrint('Error leaving station ${station.name}: $e');
                    }
                  }
                }
              }

              await authProvider.logout();
              chatProvider.disconnect();
              chatProvider.disconnectNotifications();

              final nav = NavigationService.navigatorKey.currentState;
              if (nav == null) return;
              nav.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const AuthWrapper()),
                (route) => false,
              );
            },
            child: const Text('Log Out',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}

String _formatUserType(dynamic value) {
  final raw = value?.toString().trim();
  if (raw == null || raw.isEmpty) return 'Staff';
  return raw
      .split(RegExp(r'[_\s-]+'))
      .where((part) => part.isNotEmpty)
      .map((part) =>
          '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')
      .join(' ');
}

class _StaffDrawerSectionTitle extends StatelessWidget {
  final String text;

  const _StaffDrawerSectionTitle(this.text);

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

class _StaffDrawerNavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _StaffDrawerNavTile({
    required this.icon,
    required this.label,
    required this.onTap,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
