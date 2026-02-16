import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../models/room.dart';
import '../theme/app_theme.dart';
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
        title: const Text('Staff Chat'),
        actions: [
          // Station Dropdown
          PopupMenuButton<void>(
            icon: const Icon(Icons.hub),
            tooltip: 'Manage Stations',
            itemBuilder: (context) {
              if (stations.isEmpty) {
                return [
                  const PopupMenuItem(
                    enabled: false,
                    child: Text('No stations available'),
                  ),
                ];
              }
              return stations.map((station) {
                final isConnected = station.staff?.id == currentUser?.id;
                final isOccupied = station.staff != null && !isConnected;

                return PopupMenuItem(
                  enabled: !isOccupied, // Can't toggle if someone else is there
                  onTap:
                      () {}, // Handled by checkbox or row tap, but PopupMenuItem needs onTap
                  child: InkWell(
                    onTap: isOccupied
                        ? null
                        : () {
                            Navigator.pop(context); // Close menu
                            _toggleStation(station);
                          },
                    child: Row(
                      children: [
                        Checkbox(
                          value: isConnected,
                          onChanged: isOccupied
                              ? null
                              : (val) {
                                  Navigator.pop(context);
                                  _toggleStation(station);
                                },
                        ),
                        Expanded(
                          child: Text(
                            station.name,
                            style: TextStyle(
                              color: isOccupied ? Colors.grey : Colors.black,
                            ),
                          ),
                        ),
                        if (isOccupied)
                          Text(
                            '(${station.staff?.username})',
                            style: const TextStyle(
                                fontSize: 10, color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                );
              }).toList();
            },
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
                            Expanded(
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
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _getUserTypeColor(room),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: Colors.white.withOpacity(0.2)),
                                ),
                                child: Text(
                                  _getUserTypeLabel(room)!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
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
    if (q.contains('agent')) return 'AGENT';
    if (q.contains('player')) return 'PLAYER';
    if (q.contains('high roller')) return 'VIP';
    return null; // Or default to 'USER'
  }

  Color _getUserTypeColor(Room room) {
    final label = _getUserTypeLabel(room);
    switch (label) {
      case 'AGENT':
        return Colors.blueAccent;
      case 'PLAYER':
        return Colors.green;
      case 'VIP':
        return Colors.amber.shade700;
      default:
        return Colors.grey;
    }
  }
}
