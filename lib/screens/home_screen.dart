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
import '../api/api_client.dart';
import 'package:video_player/video_player.dart';
import 'verify_user_screen.dart';
import 'post_details_screen.dart';

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
    final hasActiveEvents = _events.isNotEmpty;
    final showRoleInfo = !_isLoadingHomeInfo && _hasRenderableHomeInfo();

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
                  if (showRoleInfo) ...[
                    _buildRoleInfoSection(user),
                    const SizedBox(height: 32),
                  ] else
                    const SizedBox(height: 16),
                  if (hasActiveEvents) ...[
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
                          'Pinned Posts',
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
                  ] else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text(
                          'Pinned Posts',
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
                  ],
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.85),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                  username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    (user?.userType ?? 'Unknown').toString().toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buildVerificationBadge(context, user),
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

  bool _hasRenderableHomeInfo() {
    final title = (_homeInfo?['title'] ?? '').toString().trim();
    final subtitle = (_homeInfo?['subtitle'] ?? '').toString().trim();
    final footer = (_homeInfo?['footer'] ?? '').toString().trim();

    bool hasPoints = false;
    final dynamic pointsRaw = _homeInfo?['points'];
    if (pointsRaw is List) {
      for (final item in pointsRaw) {
        if (item is Map && (item['content'] ?? '').toString().trim().isNotEmpty) {
          hasPoints = true;
          break;
        }
      }
    }

    return title.isNotEmpty || subtitle.isNotEmpty || footer.isNotEmpty || hasPoints;
  }

  Widget _buildRoleInfoSection(dynamic user) {
    final title = (_homeInfo?['title']?.toString().trim() ?? '');
    final subtitle = (_homeInfo?['subtitle']?.toString().trim() ?? '');
    final footer = (_homeInfo?['footer']?.toString().trim() ?? '');

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

    if (_isLoadingHomeInfo || !_hasRenderableHomeInfo()) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF2B1A47).withValues(alpha: 0.9),
            const Color(0xFF1A102E).withValues(alpha: 0.95),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (title.isNotEmpty && subtitle.isNotEmpty) const SizedBox(height: 4),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 12,
              ),
            ),
          if (serverPoints.isNotEmpty) const SizedBox(height: 12),
          ...serverPoints.map((point) => Padding(
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
          if (footer.isNotEmpty) ...[
            const SizedBox(height: 2),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: Text(
                footer,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 11.5,
                  height: 1.3,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _iconFromName(String name) {
    switch (name) {
      case 'app_registration_outlined':
        return Icons.app_registration_outlined;
      case 'attach_money_outlined':
        return Icons.attach_money_outlined;
      case 'login_outlined':
        return Icons.login_outlined;
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
                    Colors.black.withValues(alpha: 0.32),
                    Colors.black.withValues(alpha: 0.95),
                  ],
                  stops: const [0.2, 1.0],
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
                        if (event.startDate != null || event.endDate != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              event.startDate != null && event.endDate != null
                                  ? '${DateFormat('MMM d, y').format(event.startDate!)} - ${DateFormat('MMM d, y').format(event.endDate!)}'
                                  : event.startDate != null
                                      ? DateFormat('MMM d, y').format(event.startDate!)
                                      : DateFormat('MMM d, y').format(event.endDate!),
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
                'No pinned posts available',
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
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PostDetailsScreen(post: post),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (post.video != null && post.video!.trim().isNotEmpty)
                    ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(20)),
                      child: _PostVideoPreview(
                        videoUrl: _resolvePostMediaUrl(post.video!),
                        fallbackImageUrl: post.image != null
                            ? _resolvePostMediaUrl(post.image!)
                            : null,
                      ),
                    )
                  else if (post.image != null && post.image!.trim().isNotEmpty)
                    ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(20)),
                      child: Image.network(
                        _resolvePostMediaUrl(post.image!),
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
                              _getFriendlyTime(post.createdAt.toLocal()),
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

  String _resolvePostMediaUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    if (trimmed.startsWith('/')) {
      return '${ApiClient.baseUrl}$trimmed';
    }
    return '${ApiClient.baseUrl}/$trimmed';
  }

  String _getFriendlyTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) {
      return diff.inMinutes == 1 ? '1 min ago' : '${diff.inMinutes} mins ago';
    }
    if (diff.inHours < 24) {
      return diff.inHours == 1 ? '1 hour ago' : '${diff.inHours} hours ago';
    }
    if (diff.inDays < 7) {
      return diff.inDays == 1 ? '1 day ago' : '${diff.inDays} days ago';
    }
    if (diff.inDays < 30) {
      final weeks = (diff.inDays / 7).floor();
      return weeks == 1 ? '1 week ago' : '$weeks weeks ago';
    }
    if (diff.inDays < 365) {
      final months = (diff.inDays / 30).floor();
      return months == 1 ? '1 month ago' : '$months months ago';
    }
    final years = (diff.inDays / 365).floor();
    return years == 1 ? '1 year ago' : '$years years ago';
  }
}

class _PostVideoPreview extends StatefulWidget {
  final String videoUrl;
  final String? fallbackImageUrl;

  const _PostVideoPreview({
    required this.videoUrl,
    this.fallbackImageUrl,
  });

  @override
  State<_PostVideoPreview> createState() => _PostVideoPreviewState();
}

class _PostVideoPreviewState extends State<_PostVideoPreview>
    with AutomaticKeepAliveClientMixin {
  static VideoPlayerController? _activePreviewController;
  static _PostVideoPreviewState? _activePreviewState;

  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;
  bool _isInitializing = false;
  bool _isPlaying = false;
  bool _isMuted = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _initController() async {
    if (_isInitializing || _ready) return;
    _isInitializing = true;
    if (mounted) setState(() {});
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      _controller = c;
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      if (!mounted) return;
      setState(() {
        _ready = true;
        _isInitializing = false;
        _isMuted = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _isInitializing = false;
      });
    }
  }

  Future<void> _togglePlayPause() async {
    if (_failed) return;
    if (!_ready || _controller == null) {
      await _initController();
      if (!_ready || _controller == null) return;
    }
    final controller = _controller!;
    if (controller.value.isPlaying) {
      await controller.pause();
      if (mounted) setState(() => _isPlaying = false);
      if (identical(_activePreviewState, this)) {
        _activePreviewState = null;
        _activePreviewController = null;
      }
      return;
    }

    if (_activePreviewController != null &&
        !identical(_activePreviewController, controller)) {
      await _activePreviewController!.pause();
      if (_activePreviewState != null && _activePreviewState!.mounted) {
        _activePreviewState!.setState(() => _activePreviewState!._isPlaying = false);
      }
    }

    await controller.play();
    _activePreviewController = controller;
    _activePreviewState = this;
    if (mounted) setState(() => _isPlaying = true);
  }

  Future<void> _openFullscreen() async {
    if (_failed) return;
    if (!_ready || _controller == null) {
      await _initController();
      if (!_ready || _controller == null) return;
    }
    final controller = _controller!;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenPostVideoPlayer(
          videoUrl: widget.videoUrl,
          externalController: controller,
          initialMuted: _isMuted,
        ),
      ),
    );

    if (!mounted) return;
    setState(() {
      _isPlaying = controller.value.isPlaying;
    });
  }

  @override
  void dispose() {
    if (identical(_activePreviewState, this)) {
      _activePreviewState = null;
      _activePreviewController = null;
    }
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final fallback = widget.fallbackImageUrl;

    if (_failed) {
      if (fallback != null && fallback.isNotEmpty) {
        return Image.network(
          fallback,
          height: 180,
          fit: BoxFit.cover,
        );
      }
      return Container(
        height: 180,
        color: Colors.black26,
        alignment: Alignment.center,
        child: const Icon(Icons.videocam_off, color: Colors.white54),
      );
    }

    if (!_ready || _controller == null) {
      if (fallback != null && fallback.isNotEmpty) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _togglePlayPause,
          child: SizedBox(
            height: 180,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  fallback,
                  fit: BoxFit.cover,
                ),
                if (_isInitializing)
                  Container(
                    color: Colors.black26,
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  const Center(
                    child: Icon(
                      Icons.play_circle_fill,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
              ],
            ),
          ),
        );
      }
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _togglePlayPause,
        child: Container(
          height: 180,
          color: Colors.black26,
          alignment: Alignment.center,
          child: _isInitializing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(
                  Icons.play_circle_fill,
                  color: Colors.white,
                  size: 44,
                ),
        ),
      );
    }

    return SizedBox(
      height: 180,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _togglePlayPause,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller!.value.size.width,
                height: _controller!.value.size.height,
                child: VideoPlayer(_controller!),
              ),
            ),
            Center(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 160),
                opacity: _isPlaying ? 0.0 : 1.0,
                child: const Icon(
                  Icons.play_circle_fill,
                  color: Colors.white,
                  size: 44,
                ),
              ),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _openFullscreen,
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(
                      Icons.fullscreen,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    final controller = _controller;
                    if (controller == null) return;
                    final nextMuted = !_isMuted;
                    await controller.setVolume(nextMuted ? 0 : 1);
                    if (mounted) {
                      setState(() => _isMuted = nextMuted);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      _isMuted ? Icons.volume_off : Icons.volume_up,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullScreenPostVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final VideoPlayerController? externalController;
  final bool initialMuted;

  const _FullScreenPostVideoPlayer({
    required this.videoUrl,
    this.externalController,
    this.initialMuted = true,
  });

  @override
  State<_FullScreenPostVideoPlayer> createState() =>
      _FullScreenPostVideoPlayerState();
}

class _FullScreenPostVideoPlayerState extends State<_FullScreenPostVideoPlayer> {
  VideoPlayerController? _controller;
  bool _ownsController = true;
  bool _ready = false;
  bool _failed = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    if (widget.externalController != null) {
      _controller = widget.externalController;
      _ownsController = false;
      _ready = _controller!.value.isInitialized;
      _controller!.setVolume(widget.initialMuted ? 0 : 1);
    } else {
      _init();
    }
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      _controller = c;
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(widget.initialMuted ? 0 : 1);
      if (!mounted) return;
      setState(() => _ready = true);
      await c.play();
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black),
        body: const Center(
          child: Icon(Icons.videocam_off, color: Colors.white54, size: 42),
        ),
      );
    }

    if (!_ready || _controller == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _showControls = !_showControls),
        child: Stack(
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: VideoPlayer(_controller!),
              ),
            ),
            if (_showControls)
              Positioned(
                top: 32,
                left: 8,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            if (_showControls)
              Center(
                child: IconButton(
                  iconSize: 56,
                  color: Colors.white,
                  icon: Icon(
                    _controller!.value.isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_fill,
                  ),
                  onPressed: () async {
                    if (_controller!.value.isPlaying) {
                      await _controller!.pause();
                    } else {
                      await _controller!.play();
                    }
                    if (mounted) setState(() {});
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
