import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../models/post.dart';
import '../models/post_comment.dart';
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
  late PostService _postService;
  final TextEditingController _commentController = TextEditingController();
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();
  List<PostComment> _comments = [];
  bool _isLoadingComments = false;
  bool _isSubmittingComment = false;
  bool _isSubmittingReply = false;
  int? _deletingCommentId;
  int? _updatingCommentId;
  int? _replyToCommentId;
  String? _replyToUsername;

  @override
  void initState() {
    super.initState();
    _currentPost = widget.post;
    final authProvider = context.read<AuthProvider>();
    _postService = PostService(authProvider.apiClient);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cached = _postService.getCachedComments(_currentPost.id);
      if (cached != null && mounted) {
        setState(() {
          _comments = cached;
          _isLoadingComments = false;
        });
      }

      _loadComments(showLoader: cached == null);
    });
  }

  @override
  void dispose() {
    _commentController.dispose();
    _replyController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadComments({bool showLoader = true}) async {
    if (showLoader) {
      setState(() => _isLoadingComments = true);
    }
    try {
      final comments = await _postService.fetchComments(_currentPost.id);
      if (!mounted) return;
      setState(() {
        _comments = comments;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingComments = false);
      }
    }
  }

  Future<void> _toggleLike() async {
    final result = await _postService.toggleLike(_currentPost.id);
    if (!mounted || result == null) return;
    final liked = result['liked'] == true;
    final likeCount = result['like_count'] is int
        ? result['like_count'] as int
        : int.tryParse('${result['like_count']}') ?? _currentPost.likeCount;
    setState(() {
      _currentPost = _currentPost.copyWith(
        isLiked: liked,
        likeCount: likeCount,
      );
    });
  }

  Future<bool> _createComment({required String content, int? parentId}) async {
    final created = await _postService.addComment(
      _currentPost.id,
      content: content,
      parentId: parentId,
    );
    if (!mounted || created == null) return false;

    setState(() {
      _currentPost = _currentPost.copyWith(
        commentCount: _currentPost.commentCount + 1,
      );
    });
    final cached = _postService.getCachedComments(_currentPost.id);
    if (cached != null) {
      setState(() {
        _comments = cached;
      });
    }
    _loadComments(showLoader: false);
    return true;
  }

  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _isSubmittingComment) return;
    setState(() => _isSubmittingComment = true);
    final success = await _createComment(content: text, parentId: null);
    if (!mounted) return;
    if (success) {
      _commentController.clear();
    }
    setState(() => _isSubmittingComment = false);
  }

  Future<void> _submitReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty || _isSubmittingReply || _replyToCommentId == null) return;
    setState(() => _isSubmittingReply = true);
    final success = await _createComment(
      content: text,
      parentId: _replyToCommentId,
    );
    if (!mounted) return;
    if (success) {
      _replyController.clear();
      _cancelReply();
    }
    setState(() => _isSubmittingReply = false);
  }

  Future<void> _editComment(PostComment comment) async {
    final controller = TextEditingController(text: comment.content);
    final newContent = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Edit Comment', style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'Update your comment',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    final content = (newContent ?? '').trim();
    if (content.isEmpty || content == comment.content) return;

    setState(() {
      _updatingCommentId = comment.id;
    });
    final updated = await _postService.updateComment(
      _currentPost.id,
      comment.id,
      content: content,
    );
    if (!mounted) return;
    if (updated != null) {
      final cached = _postService.getCachedComments(_currentPost.id);
      if (cached != null) {
        setState(() {
          _comments = cached;
        });
      }
      _loadComments(showLoader: false);
    }
    if (mounted) {
      setState(() {
        _updatingCommentId = null;
      });
    }
  }

  Future<void> _deleteComment(PostComment comment) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Delete Comment', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          'Do you want to delete this comment?',
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

    if (confirm != true) return;
    setState(() {
      _deletingCommentId = comment.id;
    });
    final deletedCount = await _postService.deleteComment(_currentPost.id, comment.id);
    if (!mounted) return;
    if (deletedCount > 0) {
      final cached = _postService.getCachedComments(_currentPost.id);
      if (cached != null) {
        setState(() {
          _comments = cached;
          _currentPost = _currentPost.copyWith(
            commentCount:
                (_currentPost.commentCount - deletedCount).clamp(0, 1000000).toInt(),
          );
        });
      } else {
        setState(() {
          _currentPost = _currentPost.copyWith(
            commentCount:
                (_currentPost.commentCount - deletedCount).clamp(0, 1000000).toInt(),
          );
        });
      }
      _loadComments(showLoader: false);
    }
    if (mounted) {
      setState(() {
        _deletingCommentId = null;
      });
    }
  }

  void _startReply(PostComment comment) {
    setState(() {
      _replyToCommentId = comment.id;
      _replyToUsername = comment.author?.username;
    });
    _replyController.clear();
  }

  void _cancelReply() {
    setState(() {
      _replyToCommentId = null;
      _replyToUsername = null;
    });
    _replyController.clear();
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context, _currentPost),
        ),
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
                  const SizedBox(height: 16),
                  _buildInteractionBar(),
                  const SizedBox(height: 16),
                  _buildCommentsBlock(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInteractionBar() {
    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _toggleLike,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: [
                Icon(
                  _currentPost.isLiked ? Icons.favorite : Icons.favorite_border,
                  color: _currentPost.isLiked ? Colors.redAccent : AppTheme.textSecondary,
                  size: 20,
                ),
                const SizedBox(width: 6),
                Text(
                  '${_currentPost.likeCount}',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Row(
          children: [
            Icon(Icons.mode_comment_outlined, color: AppTheme.textSecondary, size: 18),
            const SizedBox(width: 6),
            Text(
              '${_currentPost.commentCount}',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCommentsSection() {
    if (_isLoadingComments) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_comments.isEmpty) {
      return Text(
        'No comments yet',
        style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.85)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _comments.map((c) => _buildCommentTile(c, depth: 0)).toList(),
    );
  }

  Widget _buildCommentsBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.forum_outlined, color: AppTheme.textPrimary, size: 18),
            const SizedBox(width: 8),
            Text(
              'Comments',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '(${_currentPost.commentCount})',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildCommentComposer(),
        const SizedBox(height: 14),
        _buildCommentsSection(),
      ],
    );
  }

  Widget _buildCommentTile(PostComment comment, {required int depth}) {
    final leftPad = depth * 14.0;
    final username = comment.author?.username ?? 'User';
    final friendlyTime = _friendlyTime(comment.createdAt.toLocal());
    final initial = username.isNotEmpty ? username[0].toUpperCase() : 'U';
    final commentAvatarUrl = _resolveCommentAvatarUrl(comment.author);
    final currentUserId = context.read<AuthProvider>().user?.id;
    final isOwnComment =
        currentUserId != null && comment.author != null && comment.author!.id == currentUserId;

    return Padding(
      padding: EdgeInsets.only(left: leftPad, bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: AppTheme.cardBorder.withValues(alpha: depth == 0 ? 0.9 : 0.65),
              width: depth == 0 ? 2 : 1.5,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 10,
                  backgroundColor: AppTheme.surface.withValues(alpha: 0.9),
                  child: (commentAvatarUrl == null || commentAvatarUrl.isEmpty)
                      ? Text(
                          initial,
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : ClipOval(
                          child: Image.network(
                            commentAvatarUrl,
                            width: 20,
                            height: 20,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Text(
                              initial,
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    username,
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                Text(
                  friendlyTime,
                  style: TextStyle(
                    color: AppTheme.textSecondary.withValues(alpha: 0.75),
                    fontSize: 10.5,
                  ),
                ),
                if (isOwnComment) ...[
                  const SizedBox(width: 4),
                  if (_deletingCommentId == comment.id || _updatingCommentId == comment.id)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.textSecondary,
                      ),
                    )
                  else
                    PopupMenuButton<String>(
                      icon:
                          Icon(Icons.more_horiz, size: 16, color: AppTheme.textSecondary),
                      color: AppTheme.surface,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 120),
                      onSelected: (value) {
                        if (value == 'edit') {
                          _editComment(comment);
                        } else if (value == 'delete') {
                          _deleteComment(comment);
                        }
                      },
                      itemBuilder: (ctx) => const [
                        PopupMenuItem<String>(
                          value: 'edit',
                          child: Text('Edit'),
                        ),
                        PopupMenuItem<String>(
                          value: 'delete',
                          child: Text('Delete'),
                        ),
                      ],
                    ),
                ],
              ],
            ),
            const SizedBox(height: 5),
            RichText(
              text: TextSpan(
                style: TextStyle(
                  color: AppTheme.textPrimary.withValues(alpha: 0.9),
                  fontSize: 13.2,
                  height: 1.32,
                ),
                children: [
                  TextSpan(text: comment.content),
                  const TextSpan(text: '  '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: GestureDetector(
                      onTap: () => _startReply(comment),
                      child: Text(
                        'Reply',
                        style: TextStyle(
                          color: AppTheme.accent,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_replyToCommentId == comment.id) ...[
              const SizedBox(height: 8),
              _buildInlineReplyComposer(),
            ],
            if (comment.replies.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...comment.replies
                  .map((reply) => _buildCommentTile(reply, depth: depth + 1)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCommentComposer() {
    const commentInputRadius = 14.0;
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surface.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(commentInputRadius),
              border: Border.all(color: AppTheme.cardBorder.withValues(alpha: 0.8)),
            ),
            child: TextField(
              controller: _commentController,
              focusNode: _commentFocusNode,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Add a comment...',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          onPressed: _isSubmittingComment ? null : _submitComment,
          style: IconButton.styleFrom(
            backgroundColor: AppTheme.accent,
            foregroundColor: Colors.white,
            minimumSize: const Size(38, 38),
          ),
          icon: _isSubmittingComment
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.send_rounded, size: 18),
        ),
      ],
    );
  }

  Widget _buildInlineReplyComposer() {
    const replyBoxRadius = 12.0;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(replyBoxRadius),
        border: Border.all(color: AppTheme.cardBorder.withValues(alpha: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Replying to ${_replyToUsername ?? 'comment'}',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _cancelReply,
                child: Icon(Icons.close, size: 16, color: AppTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _replyController,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Write a reply...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(replyBoxRadius),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(replyBoxRadius),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(replyBoxRadius),
              ),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _isSubmittingReply ? null : _submitReply,
              icon: _isSubmittingReply
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.reply_rounded, size: 16),
              label: const Text('Send Reply'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
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

  String? _resolveCommentAvatarUrl(dynamic user) {
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
