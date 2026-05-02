import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../api/api_client.dart';
import '../models/post.dart';
import '../providers/auth_provider.dart';
import '../services/post_service.dart';
import '../theme/app_theme.dart';
import 'post_details_screen.dart';

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
        title: const Text('Posts Feed'),
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: _buildBody(),
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
        final cleanContent =
            post.content.replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), '');

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: AppTheme.itemDecoration(
            customRadius: BorderRadius.circular(AppTheme.radius + 4),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radius + 4),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PostDetailsScreen(post: post),
                  ),
                );
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (post.video != null && post.video!.trim().isNotEmpty)
                    _buildVideoPreview(post)
                  else if (post.image != null && post.image!.trim().isNotEmpty)
                    _buildImagePreview(post.image!),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _buildAuthorAvatar(post.author),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _capitalizeUsername(post.author?.username ?? 'Unknown'),
                                style: TextStyle(
                                  color: AppTheme.textPrimary.withValues(alpha: 0.82),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              _getFriendlyTime(post.createdAt.toLocal()),
                              style: TextStyle(
                                color: AppTheme.textPrimary.withValues(alpha: 0.52),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          post.title,
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (cleanContent.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            cleanContent,
                            maxLines: 3,
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
      },
    );
  }

  Widget _buildAuthorAvatar(dynamic author) {
    final profileImageUrl = _resolveProfileImageUrl(author);
    final initial = _capitalizeUsername(author?.username ?? '?');
    final initialChar = initial.isNotEmpty ? initial[0] : '?';

    return CircleAvatar(
      radius: 13,
      backgroundColor: AppTheme.primary,
      backgroundImage:
          profileImageUrl != null ? NetworkImage(profileImageUrl) : null,
      child: profileImageUrl == null
          ? Text(
              initialChar,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            )
          : null,
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

  String _capitalizeUsername(String input) {
    if (input.isEmpty) return input;
    final trimmed = input.trim();
    if (trimmed.isEmpty) return input;
    return trimmed[0].toUpperCase() + trimmed.substring(1);
  }

  Widget _buildImagePreview(String imageUrl) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      child: Image.network(
        _resolvePostMediaUrl(imageUrl),
        height: 190,
        fit: BoxFit.cover,
      ),
    );
  }

  Widget _buildVideoPreview(Post post) {
    final fallbackImage = post.image?.trim().isNotEmpty == true
        ? _resolvePostMediaUrl(post.image!)
        : null;

    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radius + 4)),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (fallbackImage != null)
            Image.network(
              fallbackImage,
              height: 190,
              width: double.infinity,
              fit: BoxFit.cover,
            )
          else
            Container(
              height: 190,
              color: Colors.black26,
            ),
          Container(
            height: 190,
            color: Colors.black.withValues(alpha: 0.2),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.play_arrow, color: AppTheme.textPrimary, size: 26),
          ),
        ],
      ),
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
