import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/post.dart';
import '../theme/app_theme.dart';
import '../api/api_client.dart';

class PostDetailsScreen extends StatelessWidget {
  final Post post;

  const PostDetailsScreen({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    final cleanContent = _stripHtml(post.content);
    final friendlyCreatedAt = _getFriendlyTime(post.createdAt.toLocal());

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Post Details'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (post.video != null && post.video!.trim().isNotEmpty)
              _DetailVideoPlayer(videoUrl: _resolveMediaUrl(post.video!))
            else if (post.image != null && post.image!.trim().isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  _resolveMediaUrl(post.image!),
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 14),
            Text(
              post.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 8),
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
                Expanded(
                  child: Text(
                    post.author?.username ?? 'Unknown',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  friendlyCreatedAt,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              cleanContent,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.88),
                fontSize: 15,
                height: 1.45,
              ),
            ),
            if (post.link != null && post.link!.trim().isNotEmpty) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open Link'),
                onPressed: () async {
                  final uri = Uri.parse(post.link!.trim());
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _stripHtml(String input) {
    return input.replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), '').trim();
  }

  String _resolveMediaUrl(String rawUrl) {
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

class _DetailVideoPlayer extends StatefulWidget {
  final String videoUrl;

  const _DetailVideoPlayer({required this.videoUrl});

  @override
  State<_DetailVideoPlayer> createState() => _DetailVideoPlayerState();
}

class _DetailVideoPlayerState extends State<_DetailVideoPlayer> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      _controller = c;
      await c.initialize();
      await c.setLooping(true);
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _ready = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _controller == null) {
      return Container(
        height: 220,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: _controller!.value.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            VideoPlayer(_controller!),
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
