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

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      if (!mounted) return;
      setState(() => _isLoading = true);

      final apiClient = context.read<AuthProvider>().apiClient;
      final chatProvider = context.read<ChatProvider>();

      await Future.wait([
        chatProvider.fetchActiveChats(apiClient),
        chatProvider.fetchSupportStations(apiClient),
      ]);

      if (mounted) {
        setState(() => _isLoading = false);
        // Connect to notifications channel
        final token = context.read<AuthProvider>().accessToken;
        if (token != null) {
          chatProvider.connectNotifications(token);
        }
        // Initialize push notifications
        NotificationService.initialize(context.read<AuthProvider>().apiClient);
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
      setState(() => _isLoading = true); // Show loading during toggle
      if (isConnected) {
        await chatProvider.leaveStation(apiClient, station.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Disconnected from ${station.name}')),
        );
      } else {
        await chatProvider.joinStation(apiClient, station.id);
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
                              TextStyle(color: Colors.white.withOpacity(0.5)),
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
        color: Colors.white.withOpacity(0.05),
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
                        color: textColor.withOpacity(0.6), fontSize: 12),
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
          backgroundColor: color.withOpacity(0.15),
          foregroundColor: color,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          side: BorderSide(color: color.withOpacity(0.3)),
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

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Rollin Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.hub),
            tooltip: 'Manage Stations',
            onPressed: () => _showStationsSheet(context, stations, currentUser),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchData,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthProvider>().logout(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : activeChats.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline,
                          size: 64, color: Colors.white.withOpacity(0.2)),
                      const SizedBox(height: 16),
                      Text(
                        'No active chats',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.5), fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Connect to a station to receive chats',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.3), fontSize: 12),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: activeChats.length,
                  itemBuilder: (context, index) {
                    final room = activeChats[index];
                    // Logic to find last message or timestamp could go here if Room model supported it
                    // For now, simple list item
                    return Card(
                      color: AppTheme.surface,
                      margin: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.primary,
                          child: Text(
                            // Use clean name for avatar initial
                            _getDisplayName(room.name).isNotEmpty
                                ? _getDisplayName(room.name)[0].toUpperCase()
                                : '?',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Row(
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
                        subtitle: Text(
                          // Show Queue Name as context if available, else ID
                          room.queueName ?? 'ID: ${room.id}',
                          style:
                              TextStyle(color: Colors.white.withOpacity(0.7)),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (room.unreadCount > 0)
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Colors.redAccent,
                                  shape: BoxShape.circle,
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
                            const Icon(Icons.chevron_right,
                                color: Colors.white54),
                          ],
                        ),
                        onTap: () => _openChat(room),
                      ),
                    );
                  },
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
}
