import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../models/post.dart';
import '../providers/auth_provider.dart';
import '../services/post_service.dart';
import '../theme/app_theme.dart';
import '../api/api_client.dart';
import 'create_post_screen.dart';

class PostDetailsScreen extends StatefulWidget {
  final Post post;

  const PostDetailsScreen({super.key, required this.post});

  @override
  State<PostDetailsScreen> createState() => _PostDetailsScreenState();
}

class _PostDetailsScreenState extends State<PostDetailsScreen> {
  late Post _currentPost;

  @override
  void initState() {
    super.initState();
    _currentPost = widget.post;
  }

  Future<void> _handleDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Delete Post', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('Are you sure you want to delete this post?',
            style: TextStyle(color: AppTheme.textSecondary)),
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

    if (confirm == true && mounted) {
      final authProvider = context.read<AuthProvider>();
      final postService = PostService(authProvider.apiClient);
      final success = await postService.deletePost(_currentPost.id);
      
      if (success && mounted) {
        Navigator.pop(context, true); // Pop with refresh signal
      }
    }
  }

  Future<void> _handleEdit() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePostScreen(editPost: _currentPost),
      ),
    );

    if (result is Post && mounted) {
      setState(() {
        _currentPost = result;
      });
      Navigator.pop(context, result);
      return;
    }

    if (result == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final authProvider = context.read<AuthProvider>();
    final isAuthor = _currentPost.isAuthor(authProvider.user?.id);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Post Details'),
        actions: [
          if (isAuthor) ...[
            IconButton(
              icon: Icon(Icons.edit_outlined, color: AppTheme.textPrimary),
              onPressed: _handleEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: _handleDelete,
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Images Carousel
            if (_currentPost.images.isNotEmpty)
              _DetailsImageCarousel(images: _currentPost.images),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PostHeader(post: _currentPost),
                  const SizedBox(height: 20),
                  if (_currentPost.title.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _currentPost.title,
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  Text(
                    _currentPost.content.replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), ''),
                    style: TextStyle(
                      color: AppTheme.textPrimary.withValues(alpha: 0.8),
                      fontSize: 16,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostHeader extends StatelessWidget {
  final Post post;
  const _PostHeader({required this.post});

  @override
  Widget build(BuildContext context) {
    final username = (post.author?.username ?? '?').toString();
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';
    final imageUrl = _resolveProfileImageUrl(post.author);

    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
          child: (imageUrl == null || imageUrl.isEmpty)
              ? Text(
                  initial,
                  style:
                      TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold),
                )
              : ClipOval(
                  child: Image.network(
                    imageUrl,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Text(
                      initial,
                      style: TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              post.author?.username ?? 'Unknown Author',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            Row(
              children: [
                _getVisibilityIcon(post.visibility),
                const SizedBox(width: 4),
                Text(
                  _formatDateTime(post.createdAt.toLocal()),
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
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
    return Icon(icon, size: 12, color: AppTheme.textSecondary);
  }

  String _formatDateTime(DateTime dt) {
    return "${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
  }
}

class _DetailsImageCarousel extends StatefulWidget {
  final List<String> images;
  const _DetailsImageCarousel({required this.images});

  @override
  State<_DetailsImageCarousel> createState() => _DetailsImageCarouselState();
}

class _DetailsImageCarouselState extends State<_DetailsImageCarousel> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      height: 400,
      child: Stack(
        children: [
          PageView.builder(
            itemCount: widget.images.length,
            onPageChanged: (idx) => setState(() => _currentIndex = idx),
            itemBuilder: (ctx, idx) => InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              panEnabled: true,
              scaleEnabled: true,
              child: Center(
                child: Image.network(
                  _resolveUrl(widget.images[idx]),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.error, color: Colors.white),
                ),
              ),
            ),
          ),
          if (widget.images.length > 1)
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: widget.images.asMap().entries.map((e) {
                  return Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(
                        alpha: _currentIndex == e.key ? 0.9 : 0.3,
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
    return '$base${raw.startsWith('/') ? '' : '/'}$raw';
  }
}
