import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../models/room.dart';
import '../theme/app_theme.dart';
import '../services/notification_service.dart';
import 'chat_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
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

  Future<void> _fetchData({bool initialLoad = false, bool showLoader = false}) async {
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
          debugPrint('DashboardScreen: access token unavailable for notification WS');
        }
        // Initialize push notifications (idempotent and now safe to call repeatedly)
        NotificationService.initialize(authProvider.apiClient);

        // If staff has no active station, immediately guide them to station selection.
        if (!_autoOpenedStationSheet &&
            !_hasConnectedStation(chatProvider.supportStations, authProvider.user)) {
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
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Text(
                    'Support Rooms',
                    style: TextStyle(
                      color: Colors.white,
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
                          textColor: Colors.white,
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
                          textColor: Colors.white,
                        )),
                    const SizedBox(height: 16),
                  ],

                  // Section 3: Occupied by Others
                  if (occupied.isNotEmpty) ...[
                    _sectionHeader('Occupied', Icons.lock, Colors.white38),
                    ...occupied.map((station) => _stationTile(
                          station: station,
                          subtitle:
                              'Occupied by ${station.staff?.username ?? 'unknown'}',
                          trailing: const Icon(Icons.lock_outline,
                              color: Colors.white24, size: 18),
                          textColor: Colors.white38,
                        )),
                  ],

                  if (stations.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          'No support rooms available',
                          style:
                              TextStyle(color: Colors.white.withValues(alpha: 0.5)),
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
        color: Colors.white.withValues(alpha: 0.05),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          side: BorderSide(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );
  }

  void _openChat(Room room) {
    context.read<ChatProvider>().clearUnread(room.id);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(room: room)),
    );
  }

  @override
  Widget build(BuildContext context) {
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
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Staff Control Center'),
        actions: [
          IconButton(
            icon: const Icon(Icons.hub),
            tooltip: 'Manage Stations',
            onPressed: () => _showStationsSheet(context, stations, currentUser),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _fetchData(showLoader: true),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _showLogoutConfirmation(context),
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
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withValues(alpha: 0.28),
            AppTheme.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights, size: 14, color: Colors.white70),
              const SizedBox(width: 6),
              Text(
                'Shift Overview',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
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
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
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
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
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
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Icon(Icons.forum_outlined,
              size: 44, color: Colors.white.withValues(alpha: 0.25)),
          const SizedBox(height: 12),
          Text(
            hasConnectedStation ? 'No active chats yet' : 'No active station selected',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
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
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 12,
            ),
          ),
          if (!hasConnectedStation) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _showStationsSheet(context, stations, currentUser),
              icon: const Icon(Icons.hub),
              label: const Text('Select Station'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChatCard(Room room) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openChat(room),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppTheme.primary,
                child: Text(
                  _getDisplayName(room.name).isNotEmpty
                      ? _getDisplayName(room.name)[0].toUpperCase()
                      : '?',
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
                            _getDisplayName(room.name),
                            style: const TextStyle(
                              color: Colors.white,
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
                              style: const TextStyle(
                                color: Colors.white,
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
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (room.unreadCount > 0)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${room.unreadCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const Icon(Icons.chevron_right, color: Colors.white54),
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
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E), // Match app theme
        title: const Text('Log Out', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to log out?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context); // Close dialog

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

              authProvider.logout(); // Execute logout
            },
            child: const Text('Log Out',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}
