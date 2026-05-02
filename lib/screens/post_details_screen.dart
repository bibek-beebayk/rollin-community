import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
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
    context.watch<ThemeProvider>();
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
                borderRadius: BorderRadius.circular(AppTheme.radius),
                child: Image.network(
                  _resolveMediaUrl(post.image!),
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 14),
            Text(
              post.title,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildAuthorAvatar(),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _capitalizeUsername(post.author?.username ?? 'Unknown'),
                    style: TextStyle(
                      color: AppTheme.textPrimary.withValues(alpha: 0.9),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  friendlyCreatedAt,
                  style: TextStyle(
                    color: AppTheme.textSecondary.withValues(alpha: 0.75),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              cleanContent,
              style: TextStyle(
                color: AppTheme.textPrimary.withValues(alpha: 0.88),
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

  Widget _buildAuthorAvatar() {
    final profileImageUrl = _resolveProfileImageUrl(post.author);
    final initial = post.author?.username.isNotEmpty == true
        ? post.author!.username[0].toUpperCase()
        : '?';

    return CircleAvatar(
      radius: 14,
      backgroundColor: AppTheme.primary,
      backgroundImage:
          profileImageUrl != null ? NetworkImage(profileImageUrl) : null,
      child: profileImageUrl == null
          ? Text(
              initial,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            )
          : null,
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
  bool _failed = false;
  bool _isInitializing = false;
  bool _isPlaying = false;
  bool _isMuted = true;

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
    if (_controller!.value.isPlaying) {
      await _controller!.pause();
      if (mounted) setState(() => _isPlaying = false);
    } else {
      await _controller!.play();
      if (mounted) setState(() => _isPlaying = true);
    }
  }

  Future<void> _toggleMute() async {
    final controller = _controller;
    if (controller == null) return;
    final nextMuted = !_isMuted;
    await controller.setVolume(nextMuted ? 0 : 1);
    if (mounted) setState(() => _isMuted = nextMuted);
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
        builder: (_) => _DetailFullScreenVideoPlayer(
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
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Container(
        height: 220,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radius),
        ),
        alignment: Alignment.center,
        child: Icon(Icons.videocam_off, color: AppTheme.textSecondary.withValues(alpha: 0.75)),
      );
    }

    if (!_ready || _controller == null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _togglePlayPause,
        child: Container(
          height: 220,
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radius),
          ),
          alignment: Alignment.center,
          child: _isInitializing
              ? const CircularProgressIndicator()
              : Icon(
                  Icons.play_circle_fill,
                  color: AppTheme.textPrimary,
                  size: 56,
                ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: AspectRatio(
        aspectRatio: _controller!.value.aspectRatio,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _togglePlayPause,
          child: Stack(
            fit: StackFit.expand,
            children: [
              VideoPlayer(_controller!),
              Center(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: _isPlaying ? 0.0 : 1.0,
                  child: Icon(
                    Icons.play_circle_fill,
                    color: AppTheme.textPrimary,
                    size: 56,
                  ),
                ),
              ),
              Positioned(
                right: 10,
                bottom: 10,
                child: Material(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _openFullscreen,
                    child: Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.fullscreen,
                        color: AppTheme.textPrimary,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 10,
                top: 10,
                child: Material(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _toggleMute,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        _isMuted ? Icons.volume_off : Icons.volume_up,
                        color: AppTheme.textPrimary,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailFullScreenVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final VideoPlayerController? externalController;
  final bool initialMuted;

  const _DetailFullScreenVideoPlayer({
    required this.videoUrl,
    this.externalController,
    this.initialMuted = true,
  });

  @override
  State<_DetailFullScreenVideoPlayer> createState() =>
      _DetailFullScreenVideoPlayerState();
}

class _DetailFullScreenVideoPlayerState
    extends State<_DetailFullScreenVideoPlayer> {
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
        body: Center(
          child: Icon(Icons.videocam_off, color: AppTheme.textSecondary.withValues(alpha: 0.75), size: 42),
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
                  icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            if (_showControls)
              Center(
                child: IconButton(
                  iconSize: 56,
                  color: AppTheme.textPrimary,
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
