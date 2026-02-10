import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../models/room.dart';
import '../models/event.dart';
import '../services/event_service.dart';
import 'chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Event> _events = [];
  bool _isLoadingEvents = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchEvents());
  }

  Future<void> _fetchEvents() async {
    final authProvider = context.read<AuthProvider>();
    final eventService = EventService(authProvider.apiClient);

    try {
      final events = await eventService.getActiveEvents();
      if (mounted) {
        setState(() {
          _events = events;
          _isLoadingEvents = false;
        });
      }
    } catch (e) {
      print('Error loading events: $e');
      if (mounted) {
        setState(() {
          _isLoadingEvents = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rollin Community'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthProvider>().logout(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Welcome Section
            Text(
              'Welcome, ${user?.username}!',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Role: ${user?.userType}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Events Section
            const Text(
              'Current Events',
              style: TextStyle(
                  color: AppTheme.accent,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildEventsList(),

            const SizedBox(height: 32),

            // Support Action
            _buildActionButton(
              context,
              icon: Icons.chat_bubble_outline,
              label: 'Contact Support',
              onTap: () => _openSupportChat(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventsList() {
    if (_isLoadingEvents) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_events.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          children: [
            const Icon(Icons.event_busy, color: Colors.white54, size: 48),
            const SizedBox(height: 12),
            const Text(
              'No events currently active',
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 220,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _events.length,
        itemBuilder: (context, index) {
          final event = _events[index];
          final screenWidth = MediaQuery.of(context).size.width;
          final cardWidth = screenWidth > 600 ? 300.0 : screenWidth * 0.8;

          return Container(
            width: cardWidth,
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              image: event.bannerImage != null
                  ? DecorationImage(
                      image: NetworkImage(event.bannerImage!),
                      fit: BoxFit.cover,
                      colorFilter: ColorFilter.mode(
                          Colors.black.withOpacity(0.6), BlendMode.darken),
                    )
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  // TODO: Show event details
                },
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        event.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      if (event.startDate != null)
                        Text(
                          DateFormat('MMM d, y').format(event.startDate!),
                          style: const TextStyle(
                            color: AppTheme.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        event.description,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 12,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionButton(BuildContext context,
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return Center(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withOpacity(0.4),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSupportChat(BuildContext context) async {
    final authProvider = context.read<AuthProvider>();
    try {
      final response = await authProvider.apiClient.get('/api/rooms/');

      List<dynamic> data = [];
      if (response is Map && response.containsKey('data')) {
        data = response['data'];
      } else if (response is List) {
        data = response;
      }
      if (response is Map && response.containsKey('results')) {
        data = response['results'];
      }

      if (data.isNotEmpty) {
        final roomData = data[0];
        final room = Room.fromJson(roomData);

        if (context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(room: room),
            ),
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'No active support session found. Please contact admin if this persists.')),
          );
        }
      }
    } catch (e) {
      print('Error opening support chat: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to connect: $e')),
        );
      }
    }
  }
}
