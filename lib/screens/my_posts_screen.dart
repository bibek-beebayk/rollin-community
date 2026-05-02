import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models/post.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/post_service.dart';
import '../theme/app_theme.dart';
import 'create_post_screen.dart';
import 'post_details_screen.dart';

class MyPostsScreen extends StatefulWidget {
  const MyPostsScreen({super.key});

  @override
  State<MyPostsScreen> createState() => _MyPostsScreenState();
}

class _MyPostsScreenState extends State<MyPostsScreen> {
  bool _isLoading = true;
  List<Post> _posts = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchMyPosts();
    });
  }

  Future<void> _fetchMyPosts() async {
    final authProvider = context.read<AuthProvider>();
    final postService = PostService(authProvider.apiClient);

    try {
      final posts = await postService.getMyPosts();
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading my posts: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openCreatePost() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreatePostScreen()),
    );
    if (!mounted || result == null) return;
    if (result is Post) {
      final createdPost = result;
      setState(() {
        _posts.removeWhere((p) => p.id == createdPost.id);
        _posts.insert(0, createdPost);
      });
      return;
    }
    if (result == true) {
      await _fetchMyPosts();
    }
  }

  Future<void> _openPostDetails(Post post) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PostDetailsScreen(post: post)),
    );
    if (!mounted || result == null) return;
    if (result is Post) {
      setState(() {
        final idx = _posts.indexWhere((p) => p.id == result.id);
        if (idx >= 0) {
          _posts[idx] = result;
        } else {
          _posts.insert(0, result);
        }
      });
      return;
    }
    if (result == true) {
      await _fetchMyPosts();
    }
  }

  Future<void> _openEditPost(Post post) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CreatePostScreen(editPost: post)),
    );
    if (!mounted || result == null) return;
    if (result is Post) {
      setState(() {
        final idx = _posts.indexWhere((p) => p.id == result.id);
        if (idx >= 0) {
          _posts[idx] = result;
        }
      });
      return;
    }
    if (result == true) {
      await _fetchMyPosts();
    }
  }

  Future<void> _deletePost(Post post) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Delete Post', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          'Are you sure you want to delete this post?',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final authProvider = context.read<AuthProvider>();
    final postService = PostService(authProvider.apiClient);
    var success = await postService.deletePost(post.id);
    if (!success) {
      success = await _verifyPostDeleted(post.id, postService);
    }
    if (!mounted) return;
    if (success) {
      setState(() {
        _posts.removeWhere((p) => p.id == post.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Post deleted')),
      );
      await _fetchMyPosts();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete post')),
      );
    }
  }

  Future<bool> _verifyPostDeleted(int postId, PostService postService) async {
    try {
      final posts = await postService.getMyPosts();
      return posts.every((p) => p.id != postId);
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('My Posts'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreatePost,
        backgroundColor: AppTheme.accent,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchMyPosts,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _posts.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 56,
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.edit_note_outlined,
                              size: 52,
                              color: AppTheme.textSecondary.withValues(alpha: 0.45),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No posts yet',
                              style: TextStyle(
                                color: AppTheme.textSecondary.withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: _posts.length,
                    itemBuilder: (context, index) {
                      final post = _posts[index];
                      return _MyPostCard(
                        post: post,
                        onTap: () => _openPostDetails(post),
                        onEdit: () => _openEditPost(post),
                        onDelete: () => _deletePost(post),
                      );
                    },
                  ),
      ),
    );
  }
}

class _MyPostCard extends StatelessWidget {
  final Post post;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _MyPostCard({
    required this.post,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

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
              if (post.images.isNotEmpty)
                _MyPostImageCarousel(images: post.images)
              else if (post.video != null && post.video!.trim().isNotEmpty)
                _MyVideoPreviewPlaceholder(post: post),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _MyAuthorAvatar(author: post.author),
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
                                  _visibilityIcon(post.visibility),
                                  const SizedBox(width: 4),
                                  Text(
                                    _friendlyTime(post.createdAt.toLocal()),
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
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text('Edit'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.accent,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: onDelete,
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: const Text('Delete'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _visibilityIcon(String visibility) {
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

  String _friendlyTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${(diff.inDays / 7).floor()}w';
  }

  String _capitalizeUsername(String input) {
    if (input.isEmpty) return input;
    final trimmed = input.trim();
    if (trimmed.isEmpty) return input;
    return trimmed[0].toUpperCase() + trimmed.substring(1);
  }
}

class _MyAuthorAvatar extends StatelessWidget {
  final dynamic author;

  const _MyAuthorAvatar({required this.author});

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

class _MyPostImageCarousel extends StatefulWidget {
  final List<String> images;

  const _MyPostImageCarousel({required this.images});

  @override
  State<_MyPostImageCarousel> createState() => _MyPostImageCarouselState();
}

class _MyPostImageCarouselState extends State<_MyPostImageCarousel> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
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

class _MyVideoPreviewPlaceholder extends StatelessWidget {
  final Post post;

  const _MyVideoPreviewPlaceholder({required this.post});

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
