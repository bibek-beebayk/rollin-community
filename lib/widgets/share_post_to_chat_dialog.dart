import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/post.dart';
import '../models/room.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../services/post_service.dart';
import '../theme/app_theme.dart';
import '../api/api_client.dart';

Future<void> showSharePostToChatDialog(
  BuildContext context, {
  required Post post,
}) async {
  await showDialog(
    context: context,
    builder: (_) => _SharePostToChatDialog(post: post),
  );
}

class _SharePostToChatDialog extends StatefulWidget {
  final Post post;

  const _SharePostToChatDialog({required this.post});

  @override
  State<_SharePostToChatDialog> createState() => _SharePostToChatDialogState();
}

class _SharePostToChatDialogState extends State<_SharePostToChatDialog> {
  bool _isLoading = true;
  bool _isSending = false;
  String? _error;
  List<Room> _rooms = const [];
  final Set<int> _selectedRoomIds = <int>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRooms());
  }

  Future<void> _loadRooms() async {
    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await chat.fetchActiveChats(auth.apiClient);
      if (!mounted) return;
      final rooms = List<Room>.from(
        chat.activeChats.where((room) => room.roomType != 'support'),
      );
      rooms.sort((a, b) {
        if (a.roomType == 'group' && b.roomType != 'group') return 1;
        if (a.roomType != 'group' && b.roomType == 'group') return -1;
        return (a.name).toLowerCase().compareTo((b.name).toLowerCase());
      });
      setState(() {
        _rooms = rooms;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _share() async {
    if (_selectedRoomIds.isEmpty || _isSending) return;
    final auth = context.read<AuthProvider>();
    final postService = PostService(auth.apiClient);

    setState(() {
      _isSending = true;
      _error = null;
    });

    try {
      final result = await postService.sharePostToChats(
        widget.post.id,
        roomIds: _selectedRoomIds.toList(growable: false),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      final count = result?['shared_to_count'] is int
          ? result!['shared_to_count'] as int
          : _selectedRoomIds.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 1
                ? 'Post shared to 1 chat.'
                : 'Post shared to $count chats.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  String _displayRoomName(Room room) {
    if (room.roomType == 'group') return room.name.isNotEmpty ? room.name : 'Group';
    final counterpart = room.counterpart?.username.trim();
    if (counterpart != null && counterpart.isNotEmpty) {
      return counterpart;
    }
    return room.name.isNotEmpty ? room.name : 'Direct Chat';
  }

  String _roomTypeLabel(Room room) {
    switch (room.roomType) {
      case 'group':
        return 'Group';
      case 'direct_agent':
      default:
        return 'Direct';
    }
  }

  String _postPreviewText() {
    final title = widget.post.title.trim();
    if (title.isNotEmpty) return title;
    final clean = widget.post.content.replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), '').trim();
    if (clean.isEmpty) return 'Shared post';
    return clean.length > 120 ? '${clean.substring(0, 120)}...' : clean;
  }

  String? _firstImageUrl() {
    if (widget.post.images.isEmpty) return null;
    final raw = widget.post.images.first;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final base = ApiClient.baseUrl.endsWith('/')
        ? ApiClient.baseUrl.substring(0, ApiClient.baseUrl.length - 1)
        : ApiClient.baseUrl;
    final path = raw.startsWith('/') ? raw : '/$raw';
    return '$base$path';
  }

  String? _resolveProfileImageUrl(User? user) {
    final raw = (user?.profileThumbnail ?? user?.avatar ?? user?.profilePicture)
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

  User? _avatarUser(Room room) {
    if (room.roomType == 'group') return room.groupAdmin;
    return room.counterpart;
  }

  Widget _buildChatAvatar(Room room) {
    final user = _avatarUser(room);
    final imageUrl = _resolveProfileImageUrl(user);
    final username = (user?.username ?? _displayRoomName(room)).trim();
    final initial = username.isNotEmpty ? username[0].toUpperCase() : 'C';
    final bg = room.roomType == 'group'
        ? AppTheme.primary.withValues(alpha: 0.22)
        : AppTheme.accent.withValues(alpha: 0.22);

    return CircleAvatar(
      radius: 20,
      backgroundColor: bg,
      child: (imageUrl == null || imageUrl.isEmpty)
          ? Text(
              initial,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            )
          : ClipOval(
              child: Image.network(
                imageUrl,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Text(
                  initial,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text(
        'Share to Chats',
        style: TextStyle(color: AppTheme.textPrimary),
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPostPreview(),
            const SizedBox(height: 12),
            Text(
              'Select chats',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: AppTheme.textPrimary),
                ),
              )
            else if (_rooms.isEmpty)
              Text(
                'No direct or group chats available.',
                style: TextStyle(color: AppTheme.textSecondary),
              )
            else
              SizedBox(
                height: 280,
                child: ListView.separated(
                  itemCount: _rooms.length,
                  separatorBuilder: (_, __) => Divider(
                    color: AppTheme.cardBorder.withValues(alpha: 0.7),
                    height: 1,
                  ),
                  itemBuilder: (context, index) {
                    final room = _rooms[index];
                    final selected = _selectedRoomIds.contains(room.id);
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        setState(() {
                          if (selected) {
                            _selectedRoomIds.remove(room.id);
                          } else {
                            _selectedRoomIds.add(room.id);
                          }
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppTheme.accent.withValues(alpha: 0.16)
                              : AppTheme.background.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? AppTheme.accent.withValues(alpha: 0.8)
                                : AppTheme.cardBorder.withValues(alpha: 0.75),
                          ),
                        ),
                        child: Row(
                          children: [
                            _buildChatAvatar(room),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _displayRoomName(room),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _roomTypeLabel(room),
                                    style: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Checkbox(
                              value: selected,
                              onChanged: (_) {
                                setState(() {
                                  if (selected) {
                                    _selectedRoomIds.remove(room.id);
                                  } else {
                                    _selectedRoomIds.add(room.id);
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSending ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
        ),
        FilledButton(
          onPressed: (_isSending || _isLoading || _selectedRoomIds.isEmpty)
              ? null
              : _share,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
          child: _isSending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Send'),
        ),
      ],
    );
  }

  Widget _buildPostPreview() {
    final imageUrl = _firstImageUrl();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder.withValues(alpha: 0.8)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imageUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                imageUrl,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 56,
                  height: 56,
                  color: AppTheme.surface.withValues(alpha: 0.7),
                  alignment: Alignment.center,
                  child: Icon(Icons.image_outlined, color: AppTheme.textSecondary),
                ),
              ),
            )
          else
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppTheme.surface.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.article_outlined, color: AppTheme.textSecondary),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Post Preview',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _postPreviewText(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
