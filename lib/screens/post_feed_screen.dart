import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../api/api_client.dart';
import '../models/post.dart';
import '../providers/auth_provider.dart';
import '../services/post_service.dart';
import '../theme/app_theme.dart';
import 'post_details_screen.dart';
import 'create_post_screen.dart';

class PostFeedScreen extends StatefulWidget {
  const PostFeedScreen({super.key});

  @override
  State<PostFeedScreen> createState() => _PostFeedScreenState();
}

class _PostFeedScreenState extends State<PostFeedScreen> {
  List<Post> _posts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchPosts();
    });
  }

  Future<void> _fetchPosts() async {
    final authProvider = context.read<AuthProvider>();
    final postService = PostService(authProvider.apiClient);

    try {
      final posts = await postService.getFeedPosts();
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading posts feed: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _onRefresh() => _fetchPosts();

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Community Feed'),
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: _buildBody(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreatePostScreen()),
          );
          if (result != null) {
            _fetchPosts();
          }
        },
        backgroundColor: AppTheme.accent,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_posts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 56),
            child: Column(
              children: [
                Icon(
                  Icons.feed_outlined,
                  color: AppTheme.textSecondary.withValues(alpha: 0.4),
                  size: 48,
                ),
                const SizedBox(height: 12),
                Text(
                  'No posts available',
                  style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _posts.length,
      itemBuilder: (context, index) {
        final post = _posts[index];
        return _PostCard(
          post: post,
          onTap: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PostDetailsScreen(post: post),
              ),
            );
            if (result != null) {
              _fetchPosts();
            }
          },
        );
      },
    );
  }
}

class _PostCard extends StatelessWidget {
  final Post post;
  final VoidCallback onTap;

  const _PostCard({required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cleanContent = post.content.replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), '');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: AppTheme.itemDecoration(
        customRadius: BorderRadius.circular(AppTheme.radius + 4),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radius + 4),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Multi-Image Carousel
              if (post.images.isNotEmpty)
                _PostImageCarousel(images: post.images)
              else if (post.video != null && post.video!.trim().isNotEmpty)
                _VideoPreviewPlaceholder(post: post),

              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _AuthorAvatar(author: post.author),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _capitalizeUsername(post.author?.username ?? 'Unknown'),
                                style: TextStyle(
                                  color: AppTheme.textPrimary.withValues(alpha: 0.82),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Row(
                                children: [
                                  _getVisibilityIcon(post.visibility),
                                  const SizedBox(width: 4),
                                  Text(
                                    _getFriendlyTime(post.createdAt.toLocal()),
                                    style: TextStyle(
                                      color: AppTheme.textPrimary.withValues(alpha: 0.52),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (post.title.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        post.title,
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                    if (cleanContent.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        cleanContent,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.textPrimary.withValues(alpha: 0.72),
                          fontSize: 13.5,
                          height: 1.4,
                        ),
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
  }

  Widget _getVisibilityIcon(String visibility) {
    IconData icon;
    switch (visibility) {
      case 'private':
        icon = Icons.lock;
        break;
      case 'connections':
        icon = Icons.people;
        break;
      default:
        icon = Icons.public;
    }
    return Icon(icon, size: 10, color: AppTheme.textPrimary.withValues(alpha: 0.4));
  }

  String _capitalizeUsername(String input) {
    if (input.isEmpty) return input;
    final trimmed = input.trim();
    if (trimmed.isEmpty) return input;
    return trimmed[0].toUpperCase() + trimmed.substring(1);
  }

  String _getFriendlyTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${(diff.inDays / 7).floor()}w';
  }
}

class _PostImageCarousel extends StatefulWidget {
  final List<String> images;

  const _PostImageCarousel({required this.images});

  @override
  State<_PostImageCarousel> createState() => _PostImageCarouselState();
}

class _PostImageCarouselState extends State<_PostImageCarousel> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 280,
          child: Stack(
            children: [
              PageView.builder(
                itemCount: widget.images.length,
                onPageChanged: (index) => setState(() => _currentIndex = index),
                itemBuilder: (context, index) {
                  return Container(
                    color: Colors.black.withValues(alpha: 0.05),
                    child: Image.network(
                      _resolveUrl(widget.images[index]),
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Center(child: CircularProgressIndicator());
                      },
                      errorBuilder: (context, error, stackTrace) =>
                          const Center(child: Icon(Icons.error_outline)),
                    ),
                  );
                },
              ),
              if (widget.images.length > 1)
                Positioned(
                  bottom: 12,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: widget.images.asMap().entries.map((entry) {
                      return Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(
                            alpha: _currentIndex == entry.key ? 0.9 : 0.4,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _resolveUrl(String raw) {
    if (raw.startsWith('http')) return raw;
    final base = ApiClient.baseUrl.endsWith('/')
        ? ApiClient.baseUrl.substring(0, ApiClient.baseUrl.length - 1)
        : ApiClient.baseUrl;
    final path = raw.startsWith('/') ? raw : '/$raw';
    return '$base$path';
  }
}

class _AuthorAvatar extends StatelessWidget {
  final dynamic author;
  const _AuthorAvatar({required this.author});

  @override
  Widget build(BuildContext context) {
    final username = (author?.username ?? '?').toString();
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';
    final imageUrl = _resolveProfileImageUrl(author);

    if (imageUrl == null || imageUrl.isEmpty) {
      return CircleAvatar(
        radius: 14,
        backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
        child: Text(
          initial,
          style: TextStyle(
            color: AppTheme.primary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: 14,
      backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
      child: ClipOval(
        child: Image.network(
          imageUrl,
          width: 28,
          height: 28,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Text(
            initial,
            style: TextStyle(
              color: AppTheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  String? _resolveProfileImageUrl(dynamic user) {
    final raw =
        (user?.profileThumbnail ?? user?.avatar ?? user?.profilePicture)
            ?.toString()
            .trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;

    final base = ApiClient.baseUrl.endsWith('/')
        ? ApiClient.baseUrl.substring(0, ApiClient.baseUrl.length - 1)
        : ApiClient.baseUrl;
    final path = raw.startsWith('/') ? raw : '/$raw';
    return '$base$path';
  }
}

class _VideoPreviewPlaceholder extends StatelessWidget {
  final Post post;
  const _VideoPreviewPlaceholder({required this.post});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      color: Colors.black12,
      child: const Center(
        child: Icon(Icons.play_circle_outline, size: 48, color: Colors.white54),
      ),
    );
  }
}
