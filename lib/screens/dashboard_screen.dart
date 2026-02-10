import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../models/room.dart';
import '../theme/app_theme.dart';
import 'chat_screen.dart'; // We will create this next

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Room> _supportRooms = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRooms();
  }

  Future<void> _fetchRooms() async {
    try {
      if (!mounted) return;
      setState(() => _isLoading = true);

      final api = context.read<AuthProvider>().apiClient;

      // 1. Fetch Support Rooms (Queues)
      final response = await api.get('/api/support-rooms/');

      final List<dynamic> jsonList =
          (response is Map && response.containsKey('data'))
              ? response['data']
              : response;

      print(
          'Dashboard: Fetched ${jsonList.length} rooms. First item: ${jsonList.isNotEmpty ? jsonList.first : "empty"}');

      final allRooms = jsonList.map((j) => Room.fromJson(j)).toList();

      if (mounted) {
        setState(() {
          _supportRooms = allRooms;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load rooms: $e')));
      }
    }
  }

  Future<void> _enterRoom(Room room) async {
    try {
      final api = context.read<AuthProvider>().apiClient;
      await api.post('/api/support-rooms/${room.id}/enter/');
      await _fetchRooms(); // Refresh to get the new chat room in active chats

      if (mounted) {
        // After refreshing, try to find the linked chat room
        // The room object itself should now reflect the staff assignment
        // so we can just open it directly.
        _openChat(room);
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to enter room: $e')));
    }
  }

  Future<void> _openChat(Room room) async {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(room: room)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthProvider>().logout(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchRooms,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionHeader(title: 'Support Workstations'),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount:
                            MediaQuery.of(context).size.width > 600 ? 3 : 2,
                        childAspectRatio:
                            MediaQuery.of(context).size.width > 600 ? 1.2 : 1.0,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: _supportRooms.length,
                      itemBuilder: (context, index) {
                        final room = _supportRooms[index];
                        final currentUser = context.read<AuthProvider>().user;
                        final isMine = room.staff?.id == currentUser?.id;
                        final isOccupied = room.staff != null && !isMine;

                        return _SupportRoomCard(
                          room: room,
                          isMine: isMine,
                          isOccupied: isOccupied,
                          onTap: () {
                            if (isMine) {
                              _openChat(room);
                            } else if (!isOccupied) _enterRoom(room);
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _SupportRoomCard extends StatelessWidget {
  final Room room;
  final bool isMine;
  final bool isOccupied;
  final VoidCallback onTap;

  const _SupportRoomCard({
    required this.room,
    required this.isMine,
    required this.isOccupied,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color bgColor = Colors.white.withOpacity(0.05);
    Color borderColor = Colors.transparent;
    String statusText = 'Available';
    Color statusColor = Colors.green;

    if (isMine) {
      bgColor = AppTheme.primary.withOpacity(0.2);
      borderColor = AppTheme.primary;
      statusText = 'Active';
    } else if (isOccupied) {
      bgColor = Colors.black.withOpacity(0.2);
      statusText = 'Occupied';
      statusColor = Colors.red;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: isMine
              ? [
                  BoxShadow(
                    color: AppTheme.primary.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isMine
                    ? Icons.chat_bubble
                    : isOccupied
                        ? Icons.lock
                        : Icons.lock_open,
                color: Colors.white,
                size: 20,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 12,
                    color: statusColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (isOccupied && room.staff != null)
                  Text(
                    'by ${room.staff!.username}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withOpacity(0.5),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
