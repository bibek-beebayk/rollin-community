import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../models/event.dart';
import '../models/post.dart';
import '../services/event_service.dart';
import '../services/post_service.dart';
import '../services/notification_service.dart';
import 'verify_user_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Event> _events = [];
  bool _isLoadingEvents = true;

  List<Post> _posts = [];
  bool _isLoadingPosts = true;
  Map<String, dynamic>? _homeInfo;
  bool _isLoadingHomeInfo = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchEvents();
      _fetchPosts();
      _fetchHomeInfo();
    });
  }

  Future<void> _fetchEvents() async {
    final authProvider = context.read<AuthProvider>();
    final eventService = EventService(authProvider.apiClient);

    // Initialize notifications (permissions + FCM token)
    NotificationService.initialize(authProvider.apiClient);

    try {
      final events = await eventService.getActiveEvents();
      if (mounted) {
        setState(() {
          _events = events;
          _isLoadingEvents = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading events: $e');
      if (mounted) {
        setState(() {
          _isLoadingEvents = false;
        });
      }
    }
  }

  Future<void> _fetchPosts() async {
    final authProvider = context.read<AuthProvider>();
    final postService = PostService(authProvider.apiClient);

    try {
      final posts = await postService.getLatestPosts();
      if (mounted) {
        setState(() {
          _posts = posts;
          _isLoadingPosts = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading posts: $e');
      if (mounted) {
        setState(() {
          _isLoadingPosts = false;
        });
      }
    }
  }

  Future<void> _onRefresh() async {
    // Optional: Only show loading indicators if desired,
    // but RefreshIndicator already has a spinner.
    await Future.wait([
      _fetchEvents(),
      _fetchPosts(),
      _fetchHomeInfo(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Rollin Community',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.background,
              AppTheme.surface,
              AppTheme.background,
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _onRefresh,
            color: AppTheme.accent,
            backgroundColor: AppTheme.surface,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildProfileCard(context, user),
                  const SizedBox(height: 16),
                  _buildRoleInfoSection(user),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text(
                        'Live Events',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildEventsList(),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text(
                        'Latest Posts',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildLatestPostsList(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context, dynamic user) {
    final username = user?.username ?? 'Guest';
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.85),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back,',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  username,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        (user?.userType ?? 'Unknown').toString().toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildVerificationBadge(context, user),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationBadge(BuildContext context, dynamic user) {
    if (user == null) return const SizedBox.shrink();

    if (user.isVerified) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.blueAccent.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified, color: Colors.blueAccent, size: 12),
            const SizedBox(width: 4),
            Text(
              'VERIFIED',
              style: TextStyle(
                color: Colors.blueAccent.shade100,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    } else if (user.verificationStatus == 'pending') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orangeAccent.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.pending, color: Colors.orangeAccent, size: 12),
            const SizedBox(width: 4),
            Text(
              'PENDING',
              style: TextStyle(
                color: Colors.orangeAccent.shade100,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    } else {
      return GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const VerifyUserScreen()),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.redAccent.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.security, color: Colors.redAccent, size: 12),
              const SizedBox(width: 4),
              Text(
                'VERIFY NOW',
                style: TextStyle(
                  color: Colors.redAccent.shade100,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _fetchHomeInfo() async {
    final authProvider = context.read<AuthProvider>();
    try {
      final response = await authProvider.apiClient.get('/api/auth/home-info/');
      final data = (response is Map && response.containsKey('data'))
          ? response['data']
          : response;
      if (mounted) {
        setState(() {
          _homeInfo = data is Map<String, dynamic> ? data : null;
          _isLoadingHomeInfo = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading home info: $e');
      if (mounted) {
        setState(() {
          _isLoadingHomeInfo = false;
        });
      }
    }
  }

  Widget _buildRoleInfoSection(dynamic user) {
    final userType = (user?.userType ?? '').toString().toLowerCase();
    final isAgent = userType == 'agent';
    final title = (_homeInfo?['title']?.toString().trim().isNotEmpty ?? false)
        ? _homeInfo!['title'].toString().trim()
        : (isAgent ? 'Agent Info' : 'Player Info');
    final subtitle =
        (_homeInfo?['subtitle']?.toString().trim().isNotEmpty ?? false)
            ? _homeInfo!['subtitle'].toString().trim()
            : (isAgent
                ? 'Key updates and support workflow for agents.'
                : 'Important updates and quick guidance for players.');

    final serverPoints = <Map<String, String>>[];
    final dynamic pointsRaw = _homeInfo?['points'];
    if (pointsRaw is List) {
      for (final item in pointsRaw) {
        if (item is Map) {
          final content = (item['content'] ?? '').toString().trim();
          if (content.isEmpty) continue;
          final icon = (item['icon'] ?? 'info_outline').toString().trim();
          serverPoints.add({
            'icon': icon.isEmpty ? 'info_outline' : icon,
            'content': content,
          });
        }
      }
    }

    final fallback = isAgent
        ? const [
            {'icon': 'campaign_outlined', 'content': 'Keep your queue updates enabled for faster response handling.'},
            {'icon': 'schedule_outlined', 'content': 'Watch your active support windows to avoid missed replies.'},
            {'icon': 'support_agent_outlined', 'content': 'Use chat for escalations and attach files when needed.'},
          ]
        : const [
            {'icon': 'verified_user_outlined', 'content': 'Complete verification to unlock full support flow.'},
            {'icon': 'chat_bubble_outline', 'content': 'Use the chat tab to connect with support instantly.'},
            {'icon': 'notifications_active_outlined', 'content': 'Keep notifications enabled for faster assistance updates.'},
          ];
    final displayPoints =
        serverPoints.isNotEmpty ? serverPoints : fallback.cast<Map<String, String>>();

    if (_isLoadingHomeInfo) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              'Loading info...',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          ...displayPoints.map((point) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                        _iconFromName((point['icon'] ?? 'info_outline').toString()),
                        size: 16, color: AppTheme.accent.withValues(alpha: 0.9)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        (point['content'] ?? '').toString(),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12.5,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  IconData _iconFromName(String name) {
    switch (name) {
      case 'campaign_outlined':
        return Icons.campaign_outlined;
      case 'schedule_outlined':
        return Icons.schedule_outlined;
      case 'support_agent_outlined':
        return Icons.support_agent_outlined;
      case 'verified_user_outlined':
        return Icons.verified_user_outlined;
      case 'chat_bubble_outline':
        return Icons.chat_bubble_outline;
      case 'notifications_active_outlined':
        return Icons.notifications_active_outlined;
      case 'info_outline':
      default:
        return Icons.info_outline;
    }
  }

  Widget _buildEventsList() {
    if (_isLoadingEvents) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_events.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy,
                color: Colors.white.withValues(alpha: 0.2), size: 30),
            const SizedBox(height: 6),
            Text(
              'No events currently active',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 240,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: _events.length,
        itemBuilder: (context, index) {
          final event = _events[index];
          final screenWidth = MediaQuery.of(context).size.width;
          final cardWidth = screenWidth > 600 ? 320.0 : screenWidth * 0.75;

          return Container(
            width: cardWidth,
            margin: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
              image: event.bannerImage != null
                  ? DecorationImage(
                      image: NetworkImage(event.bannerImage!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.8),
                  ],
                  stops: const [0.4, 1.0],
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    // TODO: Show event details
                  },
                  borderRadius: BorderRadius.circular(24),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (event.startDate != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              DateFormat('MMM d, y').format(event.startDate!),
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          event.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          event.description,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 13,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLatestPostsList() {
    if (_isLoadingPosts) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_posts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.article_outlined,
                  color: Colors.white.withValues(alpha: 0.2), size: 48),
              const SizedBox(height: 12),
              Text(
                'No recent posts available',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: _posts.length,
      itemBuilder: (context, index) {
        final post = _posts[index];
        final cleanContent =
            post.content.replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), '');

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                // TODO: Navigate to Post details
              },
              borderRadius: BorderRadius.circular(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (post.image != null)
                    ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(20)),
                      child: Image.network(
                        post.image!,
                        height: 180,
                        fit: BoxFit.cover,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: AppTheme.primary,
                              child: Text(
                                post.author?.username.isNotEmpty == true
                                    ? post.author!.username[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              post.author?.username ?? 'Unknown',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              DateFormat('MMM d')
                                  .format(post.createdAt.toLocal()),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          post.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                          ),
                        ),
                        if (cleanContent.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            cleanContent,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 14,
                              height: 1.4,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
