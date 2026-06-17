import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

import 'package:intl/intl.dart';
import '../models/room.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../models/post.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../theme/app_theme.dart';
import '../api/api_client.dart';
import '../config/app_config.dart';
import 'post_details_screen.dart';

import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:convert';
// ignore_for_file: use_build_context_synchronously

import 'dart:async';

class ChatScreen extends StatefulWidget {
  final Room room;

  const ChatScreen({super.key, required this.room});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  Timer? _typingDebounceTimer;
  bool _isLoading = true;
  bool _isUploading = false;
  bool _isLoadingOlder = false;
  bool _isPinnedSectionExpanded = false;
  int? _highlightedMessageId;
  int? _menuOpenMessageId;
  Message? _replyToMessage;
  Room? _selectedChat;
  final List<PlatformFile> _selectedFiles = [];
  final Map<int, GlobalKey> _messageItemKeys = {};
  static const List<String> _emojiPalette = [
    '😀', '😁', '😂', '🤣', '😊', '😍', '😘', '😎', '🤩', '🥳',
    '🙂', '😉', '😅', '😇', '🤔', '😴', '😮', '😢', '😭', '😡',
    '👍', '👎', '👏', '🙌', '🙏', '💪', '🔥', '🎉', '💯', '✅',
    '❤️', '💙', '💚', '💛', '🧡', '💜', '🖤', '🤍', '💬', '📌',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScrollForHistory);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initQueue());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    debugPrint('DEBUG: ChatScreen dispose called');
    WidgetsBinding.instance.removeObserver(this);
    context.read<ChatProvider>().setRouteChatOpen(false);
    // REMOVED _chatProvider.disconnect() to persist connection across pushes

    _focusNode.dispose();
    _typingDebounceTimer?.cancel();
    _messageController.dispose();
    _scrollController.removeListener(_onScrollForHistory);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _focusNode.unfocus();
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'mp4', 'mov'],
      );

      if (result != null) {
        setState(() {
          _selectedFiles.addAll(result.files);
        });
      }
    } catch (e) {
      debugPrint('Error picking files: $e');
    }
  }

  void _removeFile(int index) {
    setState(() {
      _selectedFiles.removeAt(index);
    });
  }

  Future<void> _initQueue() async {
    final chatProvider = context.read<ChatProvider>();
    final authProvider = context.read<AuthProvider>();
    chatProvider.setRouteChatOpen(authProvider.isStaff);

    final isAlreadyLoaded = chatProvider.hasCachedRoom(widget.room.id);

    if (!isAlreadyLoaded) {
      if (mounted) setState(() => _isLoading = true);
    }

    // Fetch active chats for EVERYONE to get latest room data
    final fetchActiveFuture =
        chatProvider.fetchActiveChats(authProvider.apiClient).catchError((e) {
      debugPrint('Error fetching active chats: $e');
    });

    if (!isAlreadyLoaded) {
      await fetchActiveFuture;
    }

    if (authProvider.isStaff) {
      // Staff always enters a specific room from Dashboard
      if (isAlreadyLoaded) {
        _openChatThread(widget.room, isAlreadyLoaded: true);
      } else {
        await _openChatThread(widget.room);
      }
    } else {
      // Player logic: Find their active session
      Room topRoom = widget.room;
      if (!isAlreadyLoaded) {
        topRoom = chatProvider.activeChats.firstWhere(
          (r) => r.id == widget.room.id,
          orElse: () => widget.room,
        );
      }

      if (mounted) {
        setState(() {
          _selectedChat = topRoom;
        });
      }

      if (isAlreadyLoaded) {
        _openChatThread(topRoom, isAlreadyLoaded: true);
      } else {
        await _openChatThread(topRoom);
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _openChatThread(
    Room chatRoom, {
    bool isAlreadyLoaded = false,
    bool showBlockingLoader = true,
  }) async {
    if (mounted) {
      setState(() {
        _selectedChat = chatRoom;
        _isLoadingOlder = false;
        _replyToMessage = null;
        if (!isAlreadyLoaded && showBlockingLoader) {
          _isLoading = true;
        }
      });
    }

    final authProvider = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();
    final apiClient = authProvider.apiClient;

    if (apiClient.accessToken != null) {
      try {
        try {
          // Fire and forget join attempt
          apiClient.post('/api/rooms/${chatRoom.id}/join/');
        } catch (e) {
          // Ignore if already joined
        }

        chatProvider.connect(chatRoom.id, apiClient.accessToken!);

        chatProvider.connect(chatRoom.id, apiClient.accessToken!);

        if (isAlreadyLoaded) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _scrollToBottomInstant();
          });
          // Also fetch messages silently in background to catch up on any missed WS events
          chatProvider.fetchMessages(chatRoom.id);
        } else {
          if (showBlockingLoader) {
            await chatProvider.fetchMessages(chatRoom.id);
            if (mounted) {
              setState(() => _isLoading = false);
              Future.delayed(
                  const Duration(milliseconds: 100), _scrollToBottomInstant);
            }
          } else {
            // Instant switch UX: load in background without blocking overlay.
            chatProvider.fetchMessages(chatRoom.id);
            if (mounted) {
              setState(() => _isLoading = false);
            }
          }
        }
      } catch (e) {
        debugPrint('Error opening chat: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load chat: $e')),
          );
          if (mounted) setState(() => _isLoading = false);
        }
      }
    }
  }

  void _scrollToBottomInstant() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } else {
      Future.delayed(const Duration(milliseconds: 50), () {
        if (_scrollController.hasClients && mounted) {
          _scrollToBottomInstant();
        }
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_scrollController.hasClients && mounted) {
            _scrollToBottomInstant();
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    final chatProvider = context.read<ChatProvider>();
    final currentUser = context.read<AuthProvider>().user;

    if ((text.isEmpty && _selectedFiles.isEmpty) || !chatProvider.isConnected) {
      return;
    }

    if (_selectedChat == null) return;

    if (_selectedFiles.isNotEmpty) {
      try {
        if (mounted) setState(() => _isUploading = true);
        for (var file in _selectedFiles) {
          if (file.path != null) {
            await chatProvider.uploadFile(file.path!, _selectedChat!.id);
          }
        }
        if (mounted) {
          setState(() {
            _selectedFiles.clear();
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to upload file: $e')),
          );
          setState(() => _isUploading = false);
          return;
        }
      } finally {
        if (mounted) setState(() => _isUploading = false);
      }
    }

    if (text.isNotEmpty) {
      if (chatProvider.currentRoomId != null) {
        if (currentUser == null) return;
        chatProvider.sendMessage(
          chatProvider.currentRoomId!,
          text,
          replyToMessageId: _replyToMessage?.id,
          sender: currentUser,
        );
      }
      _messageController.clear();
    }
    if (mounted) {
      setState(() {
        _replyToMessage = null;
      });
    }

    _focusNode.requestFocus();
    Future.delayed(const Duration(milliseconds: 150), _scrollToBottom);
  }

  String? _resolveProfileImageUrl(User? user) {
    if (user == null) return null;
    final raw = (user.profileThumbnail ?? user.avatar ?? user.profilePicture)?.trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final normalizedPath = raw.startsWith('/') ? raw : '/$raw';
    return '${AppConfig.baseUrl}$normalizedPath';
  }

  void _onScrollForHistory() {
    if (_isLoading || _isLoadingOlder) return;
    if (!_scrollController.hasClients) return;
    final roomId = _selectedChat?.id;
    if (roomId == null) return;

    final position = _scrollController.position;
    final nearTop = position.pixels >= (position.maxScrollExtent - 180);
    if (!nearTop) return;

    _loadOlderMessages(roomId);
  }

  Future<void> _loadOlderMessages(int roomId) async {
    if (_isLoadingOlder) return;
    setState(() => _isLoadingOlder = true);
    try {
      await context.read<ChatProvider>().fetchOlderMessages(roomId);
    } finally {
      if (mounted) setState(() => _isLoadingOlder = false);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchQuickReplies() async {
    final api = context.read<AuthProvider>().apiClient;
    final response = await api.get('/api/quick-replies/');
    final data = (response is Map && response.containsKey('data'))
        ? response['data']
        : response;
    if (data is List) {
      return data.whereType<Map<String, dynamic>>().toList();
    }
    return [];
  }

  Future<void> _addQuickReply() async {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    final payload = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(
          'New Quick Reply',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              style: TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Title',
                hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.75)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: contentController,
              maxLines: 4,
              style: TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Message content',
                hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.75)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, {
              'title': titleController.text.trim(),
              'content': contentController.text.trim(),
            }),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (payload == null) return;
    final title = payload['title'] ?? '';
    final content = payload['content'] ?? '';
    if (title.isEmpty || content.isEmpty) return;
    try {
      await context.read<AuthProvider>().apiClient.post(
        '/api/quick-replies/',
        body: {'title': title, 'content': content},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quick reply saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    }
  }

  Future<void> _showQuickReplies() async {
    try {
      final replies = await _fetchQuickReplies();
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        backgroundColor: AppTheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    'Quick Replies',
                    style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700),
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.add, color: AppTheme.textPrimary),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _addQuickReply();
                    },
                  ),
                ),
                if (replies.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No quick replies yet.',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: replies.length,
                      itemBuilder: (context, index) {
                        final item = replies[index];
                        return ListTile(
                          title: Text(
                            (item['title'] ?? '').toString(),
                            style: TextStyle(color: AppTheme.textPrimary),
                          ),
                          subtitle: Text(
                            (item['content'] ?? '').toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                            onPressed: () async {
                              try {
                                final id = item['id'];
                                if (id != null) {
                                  await context
                                      .read<AuthProvider>()
                                      .apiClient
                                      .delete('/api/quick-replies/$id/');
                                }
                                if (!mounted) return;
                                Navigator.pop(ctx);
                                await _showQuickReplies();
                              } catch (_) {}
                            },
                          ),
                          onTap: () {
                            _messageController.text =
                                (item['content'] ?? '').toString();
                            _messageController.selection = TextSelection.fromPosition(
                              TextPosition(offset: _messageController.text.length),
                            );
                            _focusNode.requestFocus();
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    }
  }

  Future<void> _openInternalNote() async {
    if (_selectedChat == null) return;
    final roomId = _selectedChat!.id;
    final controller = TextEditingController();
    try {
      final response = await context
          .read<AuthProvider>()
          .apiClient
          .get('/api/rooms/$roomId/internal-note/');
      final data = (response is Map && response.containsKey('data'))
          ? response['data']
          : response;
      controller.text = (data['content'] ?? '').toString();
    } catch (_) {}

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Internal Note', style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: controller,
          maxLines: 8,
          style: TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'Add private note...',
            hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.75)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (shouldSave != true) return;
    try {
      await context.read<AuthProvider>().apiClient.patch(
            '/api/rooms/$roomId/internal-note/',
            body: {'content': controller.text.trim()},
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Internal note updated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    }
  }

  Future<void> _resolveCurrentChat() async {
    if (_selectedChat == null) return;
    final controller = TextEditingController();
    final shouldResolve = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Resolve Chat', style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: controller,
          maxLength: 240,
          maxLines: 3,
          style: TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'Resolution reason (optional)',
            hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.75)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Resolve'),
          ),
        ],
      ),
    );
    if (shouldResolve != true) return;

    try {
      await context.read<AuthProvider>().apiClient.post(
            '/api/rooms/${_selectedChat!.id}/close/',
            body: {'resolution_reason': controller.text.trim()},
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat resolved')),
      );
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    }
  }

  Future<void> _showGroupBroadcastDialog() async {
    if (_selectedChat == null) return;
    final controller = TextEditingController();
    final content = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(
          'Broadcast Message',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: TextField(
          controller: controller,
          maxLines: 5,
          style: TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'Type broadcast message',
            hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.75)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (content == null || content.isEmpty) return;
    try {
      await context.read<ChatProvider>().sendGroupBroadcast(
            context.read<AuthProvider>().apiClient,
            roomId: _selectedChat!.id,
            content: content,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Broadcast sent')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    }
  }

  Future<void> _deleteCurrentGroup() async {
    if (_selectedChat == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Delete Group', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          'This will permanently delete this group and all chat history.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await context
          .read<ChatProvider>()
          .deleteGroup(context.read<AuthProvider>().apiClient, _selectedChat!.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    }
  }

  Future<void> _leaveCurrentGroup() async {
    if (_selectedChat == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Leave Group', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          'Are you sure you want to leave this group?',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Leave')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await context
          .read<ChatProvider>()
          .leaveGroup(context.read<AuthProvider>().apiClient, _selectedChat!.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You left the group')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    }
  }

  Future<void> _showGroupMembers() async {
    if (_selectedChat == null) return;
    try {
      final members = await context
          .read<ChatProvider>()
          .fetchGroupMembers(context.read<AuthProvider>().apiClient, _selectedChat!.id);
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        backgroundColor: AppTheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  'Group Members',
                  style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700),
                ),
              ),
              if (members.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No members found.',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: members.length,
                    itemBuilder: (context, index) {
                      final member = members[index];
                      return ListTile(
                        title: Text(
                          member.username,
                          style: TextStyle(color: AppTheme.textPrimary),
                        ),
                        subtitle: Text(
                          member.userType,
                          style: TextStyle(color: AppTheme.textPrimary.withValues(alpha: 0.65)),
                        ),
                        trailing: member.userType == 'player'
                            ? TextButton(
                                onPressed: () async {
                                  try {
                                    final room = await context.read<ChatProvider>().startDirectFromGroup(
                                          context.read<AuthProvider>().apiClient,
                                          roomId: _selectedChat!.id,
                                          playerId: member.id,
                                        );
                                    if (!mounted) return;
                                    Navigator.pop(ctx);
                                    await _openChatThread(room);
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
                                    );
                                  }
                                },
                                child: const Text('Direct Chat'),
                              )
                            : null,
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // With unified dashboard, ChatScreen always shows the thread
    return _buildChatThread(context);
  }

  // _buildQueueView removed

  Widget _buildChatThread(BuildContext context) {
    context.watch<ThemeProvider>();
    final chatProvider = context.watch<ChatProvider>();
    final currentUser = context.read<AuthProvider>().user;
    final isStaffUser = context.read<AuthProvider>().isStaff;
    final isAgentUser = currentUser?.userType == 'agent';
    final isPlayerUser = currentUser?.userType == 'player';
    final isGroupChat = _selectedChat?.roomType == 'group';
    final isDirectAgentChat = _selectedChat?.roomType == 'direct_agent';
    final canUseAgentTools = currentUser != null &&
        (currentUser.userType == 'agent' || currentUser.userType == 'staff') &&
        isDirectAgentChat;
    final canManageGroup = isAgentUser && (_selectedChat?.userIsGroupAdmin ?? false);
    final canLeaveGroup = isPlayerUser && isGroupChat;
    final messages = chatProvider.messages;
    final typingUsers = chatProvider
        .typingUsersForRoom(_selectedChat?.id)
        .where((u) => _normalizeUsername(u) != _normalizeUsername(currentUser?.username ?? ''))
        .toList(growable: false);
    final pinnedMessages = messages
        .where(
          (m) =>
              m.isPinned &&
              m.type != 'system' &&
              m.type != 'notification' &&
              m.sender.id != 0 &&
              !m.content.toLowerCase().contains('switched station'),
        )
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final unreadSwitchCount = chatProvider.activeChats.fold<int>(
      0,
      (sum, room) =>
          sum +
          ((_selectedChat != null && room.id == _selectedChat!.id)
              ? 0
              : room.unreadCount),
    );
    final canSwitchConversation = chatProvider.activeChats.length > 1;
    String titleText;
    if (isStaffUser) {
      titleText = _selectedChat?.counterpart?.username ?? _getDisplayName(_selectedChat?.name ?? 'Chat');
    } else if (_selectedChat?.roomType == 'group') {
      titleText = _selectedChat?.name ?? 'Group Chat';
    } else if (_selectedChat?.roomType == 'direct_agent' &&
        _selectedChat?.counterpart != null) {
      titleText = _selectedChat!.counterpart!.username;
    } else if ((_selectedChat?.queueName != null &&
        !_selectedChat!.queueName!.startsWith('chat__'))) {
      titleText = _selectedChat!.queueName!;
    } else {
      titleText = 'Support Station';
    }
    int? latestOwnMessageId;
    if (currentUser != null) {
      for (var i = messages.length - 1; i >= 0; i--) {
        final m = messages[i];
        final isSystem = m.type == 'system' ||
            m.type == 'notification' ||
            m.sender.id == 0 ||
            m.content.startsWith('System:') ||
            m.content.toLowerCase().contains('switched station');
        if (isSystem) continue;
        final sameUserId = m.sender.id > 0 && m.sender.id == currentUser.id;
        final sameUsername =
            _normalizeUsername(m.sender.username) ==
                _normalizeUsername(currentUser.username);
        if (sameUserId || sameUsername) {
          latestOwnMessageId = m.id;
          break;
        }
      }
    }
    final canGoBack = Navigator.of(context).canPop();
    final showBackButton = isStaffUser || canGoBack;
    final appBarAvatarUrl = _selectedChat?.roomType == 'direct_agent'
        ? _resolveProfileImageUrl(_selectedChat?.counterpart)
        : null;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: showBackButton,
        leading: showBackButton
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  context.read<ChatProvider>().setRouteChatOpen(false);
                  context.read<ChatProvider>().setChatTabActive(false);
                  if (Navigator.of(context).canPop()) {
                    Navigator.pop(context);
                  }
                },
              )
            : null,
        titleSpacing: 8,
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.primary.withValues(alpha: 0.9),
              backgroundImage:
                  appBarAvatarUrl != null ? NetworkImage(appBarAvatarUrl) : null,
              child: Text(
                appBarAvatarUrl == null
                    ? (titleText.isNotEmpty ? titleText[0].toUpperCase() : '?')
                    : '',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          titleText,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).appBarTheme.titleTextStyle,
                        ),
                      ),
                      if (isStaffUser &&
                          _selectedChat != null &&
                          _getUserTypeLabel(_selectedChat!) != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getUserTypeColor(_selectedChat!),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _getUserTypeLabel(_selectedChat!)!,
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: chatProvider.isConnected
                              ? Colors.greenAccent
                              : Colors.orangeAccent,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        chatProvider.isConnected ? 'Live connection' : 'Reconnecting...',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textPrimary.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (canSwitchConversation)
            IconButton(
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.forum),
                  if (unreadSwitchCount > 0)
                    Positioned(
                      right: -8,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(minWidth: 18),
                        child: Text(
                          unreadSwitchCount > 99
                              ? '99+'
                              : '$unreadSwitchCount',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              tooltip: 'Switch Chat',
              onPressed: () => _showChatSwitcher(context),
            ),
          if (!isStaffUser &&
              (_selectedChat?.canSwitchStation ?? false))
            IconButton(
              icon: Icon(Icons.swap_horiz, color: AppTheme.textPrimary),
              tooltip: 'Switch Station',
              onPressed: () => _confirmSwitchStation(context),
            ),
          if (canUseAgentTools || canManageGroup || canLeaveGroup)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: AppTheme.textPrimary),
              color: AppTheme.surface,
              onSelected: (value) async {
                if (value == 'group_members') {
                  await _showGroupMembers();
                  return;
                }
                if (value == 'group_broadcast') {
                  await _showGroupBroadcastDialog();
                  return;
                }
                if (value == 'delete_group') {
                  await _deleteCurrentGroup();
                  return;
                }
                if (value == 'leave_group') {
                  await _leaveCurrentGroup();
                  return;
                }
                if (value == 'quick_replies') {
                  await _showQuickReplies();
                  return;
                }
                if (value == 'internal_note') {
                  await _openInternalNote();
                  return;
                }
                if (value == 'resolve_chat') {
                  await _resolveCurrentChat();
                }
              },
              itemBuilder: (context) {
                final items = <PopupMenuEntry<String>>[];
                if (canUseAgentTools) {
                  items.addAll(const [
                    PopupMenuItem<String>(
                      value: 'quick_replies',
                      child: Text('Quick Replies'),
                    ),
                    PopupMenuItem<String>(
                      value: 'internal_note',
                      child: Text('Internal Note'),
                    ),
                    PopupMenuItem<String>(
                      value: 'resolve_chat',
                      child: Text('Resolve Chat'),
                    ),
                  ]);
                }
                if (canManageGroup) {
                  items.addAll(const [
                    PopupMenuDivider(),
                    PopupMenuItem<String>(
                      value: 'group_members',
                      child: Text('Group Members'),
                    ),
                    PopupMenuItem<String>(
                      value: 'group_broadcast',
                      child: Text('Broadcast Message'),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete_group',
                      child: Text('Delete Group'),
                    ),
                  ]);
                } else if (canLeaveGroup) {
                  items.addAll(const [
                    PopupMenuDivider(),
                    PopupMenuItem<String>(
                      value: 'leave_group',
                      child: Text('Leave Group'),
                    ),
                  ]);
                }
                return items;
              },
            ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          _focusNode.unfocus();
          FocusManager.instance.primaryFocus?.unfocus();
        },
        child: Stack(
          children: [
            Column(
            children: [
              if (pinnedMessages.isNotEmpty)
                _buildPinnedMessagesStrip(
                  context,
                  pinnedMessages,
                  currentUser,
                ),
              Expanded(
                child: Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.surface.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: AppTheme.surface.withValues(alpha: 0.35)),
                  ),
                  child: messages.isEmpty && !_isLoading
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.chat_bubble_outline,
                                    size: 42,
                                    color:
                                        AppTheme.textSecondary.withValues(alpha: 0.4)),
                                const SizedBox(height: 10),
                                Text(
                                  'No messages yet',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Start the conversation below',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary.withValues(alpha: 0.7),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          padding: const EdgeInsets.all(14),
                          itemCount: messages.length + (_isLoadingOlder ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (_isLoadingOlder && index == messages.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                              );
                            }
                            final reversedIndex = messages.length - 1 - index;
                            final message = messages[reversedIndex];

                            final isSystemMessage = message.type == 'system' ||
                                message.type == 'notification' ||
                                message.sender.id == 0 ||
                                message.content.startsWith('System:') ||
                                message.content
                                    .toLowerCase()
                                    .contains('switched station');

                            if (isSystemMessage) {
                              return _SystemMessage(message: message);
                            }

                            final currentUsername =
                                _normalizeUsername(currentUser?.username ?? '');
                            final senderUsername =
                                _normalizeUsername(message.sender.username);
                            final sameUserId = currentUser?.id != null &&
                                message.sender.id > 0 &&
                                message.sender.id == currentUser!.id;
                            final sameUsername = currentUsername.isNotEmpty &&
                                senderUsername.isNotEmpty &&
                                senderUsername == currentUsername;
                            final isMe = sameUserId || sameUsername;
                            final isStaff = message.sender.isStaff ||
                                (isMe && (currentUser?.isStaff ?? false));
                            bool sameSender(Message a, Message b) {
                              if (a.sender.id > 0 && b.sender.id > 0) {
                                return a.sender.id == b.sender.id;
                              }
                              return _normalizeUsername(a.sender.username) ==
                                  _normalizeUsername(b.sender.username);
                            }

                            bool showSender = true;
                            bool compactBottom = false;

                            if (reversedIndex > 0) {
                              final olderMessage = messages[reversedIndex - 1];
                              final diff = message.timestamp
                                  .difference(olderMessage.timestamp)
                                  .inMinutes;

                              if (sameSender(olderMessage, message) &&
                                  diff.abs() < 5) {
                                showSender = false;
                              }
                            }

                            if (reversedIndex < messages.length - 1) {
                              final newerMessage = messages[reversedIndex + 1];
                              final diff = newerMessage.timestamp
                                  .difference(message.timestamp)
                                  .inMinutes;
                              if (sameSender(newerMessage, message) &&
                                  diff.abs() < 5) {
                                compactBottom = true;
                              }
                            }
                            Message? replySourceMessage;
                            final replyId = message.replyToMessageId;
                            if (replyId != null) {
                              final idx =
                                  messages.indexWhere((m) => m.id == replyId);
                              if (idx != -1) {
                                replySourceMessage = messages[idx];
                              }
                            }

                            return _SwipeToReplyWrapper(
                              key: _messageItemKeys.putIfAbsent(
                                message.id,
                                () => GlobalKey(),
                              ),
                              isMe: isMe,
                              onReply: () => _setReplyMessage(message),
                              child: _MessageBubble(
                                message: message,
                                isStaff: isStaff,
                                isMe: isMe,
                                isCurrentUserStaff: currentUser?.isStaff ?? false,
                                showSender: showSender,
                                compactBottom: compactBottom,
                                showStatus: isMe && message.id == latestOwnMessageId,
                                isHighlighted:
                                    _highlightedMessageId == message.id ||
                                        _menuOpenMessageId == message.id,
                                replySourceMessage: replySourceMessage,
                                onMenuVisibilityChanged: (isOpen) {
                                  if (!mounted) return;
                                  setState(() {
                                    if (isOpen) {
                                      _menuOpenMessageId = message.id;
                                    } else if (_menuOpenMessageId == message.id) {
                                      _menuOpenMessageId = null;
                                    }
                                  });
                                },
                                onCopy: () => _copyMessage(message),
                                onPinToggle: () => _togglePinMessage(message),
                                onEdit:
                                    isMe ? () => _editMessage(message) : null,
                                onDelete:
                                    isMe ? () => _deleteMessage(message) : null,
                              ),
                            );
                          },
                        ),
                ),
              ),
              if (_isUploading)
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppTheme.cardBorder),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 8),
                      Text('Uploading attachments...',
                          style: TextStyle(
                              color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
              if (typingUsers.isNotEmpty)
                _buildTypingIndicator(typingUsers),
              _buildInputArea(),
            ],
          ),
          if (_isLoading)
            Container(
              color: AppTheme.background,
              child: const Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showChatSwitcher(BuildContext context) async {
    _focusNode.unfocus();
    FocusScope.of(context).unfocus();

    final chatProvider = context.read<ChatProvider>();
    final activeChats = chatProvider.activeChats;
    String roomTitle(Room room) {
      if (room.roomType == 'support') {
        final currentUser = context.read<AuthProvider>().user;
        final isStaffUser = currentUser?.isStaff ?? false;
        if (isStaffUser) {
          return room.counterpart?.username ?? _getDisplayName(room.name);
        }
        return 'Support Chat';
      }
      if (room.roomType == 'group') {
        return room.name;
      }
      if (room.roomType == 'direct_agent' && room.counterpart != null) {
        return room.counterpart!.username;
      }
      if ((room.queueName != null && !room.queueName!.startsWith('chat__'))) {
        return room.queueName!;
      }
      return _getDisplayName(room.name);
    }

    String roomSubtitle(Room room) {
      if (room.roomType == 'direct_agent') return 'Direct chat';
      if (room.roomType == 'group') return '${room.groupMemberCount} members';
      return room.queueName ?? 'ID: ${room.id}';
    }

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        if (activeChats.isEmpty) {
          return SizedBox(
            height: 180,
            child: Center(
              child: Text(
                'No active chats available',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                decoration: BoxDecoration(
                  color: AppTheme.cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Switch Conversation',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: activeChats.length,
                  separatorBuilder: (_, __) =>
                      Divider(color: AppTheme.cardBorder),
                  itemBuilder: (context, index) {
                    final room = activeChats[index];
                    final isCurrent = _selectedChat?.id == room.id;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isCurrent
                            ? AppTheme.accent
                            : AppTheme.primary.withValues(alpha: 0.9),
                        backgroundImage: room.roomType == 'direct_agent'
                            ? (_resolveProfileImageUrl(room.counterpart) != null
                                ? NetworkImage(
                                    _resolveProfileImageUrl(room.counterpart)!,
                                  )
                                : null)
                            : null,
                        child: room.roomType != 'direct_agent' ||
                                _resolveProfileImageUrl(room.counterpart) == null
                            ? Text(
                                roomTitle(room).isNotEmpty
                                    ? roomTitle(room)[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  color: isCurrent ? Colors.black : AppTheme.textPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                      title: Text(
                        roomTitle(room),
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight:
                              isCurrent ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        roomSubtitle(room),
                        style: TextStyle(
                            color: AppTheme.textSecondary.withValues(alpha: 0.8)),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (room.unreadCount > 0)
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${room.unreadCount}',
                                style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          Icon(
                            isCurrent ? Icons.check_circle : Icons.chevron_right,
                            color: isCurrent
                                ? Colors.greenAccent
                                : AppTheme.textSecondary.withValues(alpha: 0.75),
                          ),
                        ],
                      ),
                      onTap: () async {
                        Navigator.pop(ctx);
                        if (isCurrent) return;
                        chatProvider.clearUnread(room.id);
                        final hasCache = chatProvider.hasCachedRoom(room.id);
                        await _openChatThread(
                          room,
                          isAlreadyLoaded: hasCache,
                          showBlockingLoader: false,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    if (mounted) {
      _focusNode.unfocus();
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  Widget _buildPinnedMessagesStrip(
    BuildContext context,
    List<Message> pinnedMessages,
    User? currentUser,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              setState(() {
                _isPinnedSectionExpanded = !_isPinnedSectionExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Row(
                children: [
                  Icon(
                    Icons.push_pin,
                    size: 14,
                    color: Colors.amber.withValues(alpha: 0.95),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Pinned messages (${pinnedMessages.length})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.textPrimary.withValues(alpha: 0.88),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _isPinnedSectionExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.textPrimary.withValues(alpha: 0.72),
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          if (_isPinnedSectionExpanded) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: pinnedMessages.map((message) {
                  final sameUserId = currentUser?.id != null &&
                      message.sender.id > 0 &&
                      message.sender.id == currentUser!.id;
                  final sameUsername =
                      _normalizeUsername(currentUser?.username ?? '') ==
                          _normalizeUsername(message.sender.username);
                  final senderName =
                      (sameUserId || sameUsername) ? 'You' : message.sender.username;

                return Container(
                  width: 220,
                  margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.24),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppTheme.cardBorder,
                      ),
                    ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _scrollToMessage(message.id),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          senderName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.accent.withValues(alpha: 0.95),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _pinnedPreviewText(message),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.textPrimary.withValues(alpha: 0.88),
                            fontSize: 12,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('MMM d, h:mm a')
                              .format(message.timestamp.toLocal()),
                          style: TextStyle(
                            color: AppTheme.textSecondary.withValues(alpha: 0.75),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          ],
        ],
      ),
    );
  }

  String _pinnedPreviewText(Message message) {
    final content = message.content.trim();
    if (content.isNotEmpty) return content;

    final type = message.attachment?.fileType ?? '';
    if (type.startsWith('image/')) return '[Image]';
    if (type.startsWith('video/')) return '[Video]';
    if (type.isNotEmpty) return '[File]';
    return '[Message]';
  }

  Future<void> _scrollToMessage(int messageId) async {
    final messages = context.read<ChatProvider>().messages;
    final targetIndex = messages.indexWhere((m) => m.id == messageId);
    if (targetIndex < 0) return;

    if (mounted) {
      setState(() {
        _isPinnedSectionExpanded = false;
        _highlightedMessageId = messageId;
      });
    }

    final builderIndex = messages.length - 1 - targetIndex;
    const estimatedItemExtent = 120.0;

    if (_scrollController.hasClients) {
      final maxOffset = _scrollController.position.maxScrollExtent;
      final roughOffset = (builderIndex * estimatedItemExtent)
          .clamp(0.0, maxOffset)
          .toDouble();
      await _scrollController.animateTo(
        roughOffset,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final targetContext = _messageItemKeys[messageId]?.currentContext;
      if (targetContext != null) {
        Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          alignment: 0.35,
        );
      }
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      if (_highlightedMessageId == messageId) {
        setState(() => _highlightedMessageId = null);
      }
    });
  }

  Future<void> _confirmSwitchStation(BuildContext context) async {
    final authProvider = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Switch Station?'),
        content: const Text(
            'Are you sure you want to switch to a different support station? You will be moved to the next available queue.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
            child: const Text('Switch Station'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() => _isLoading = true);
      try {
        final api = authProvider.apiClient;
        await api.post('/api/rooms/switch-station/');

        if (!mounted) return;

        messenger.showSnackBar(
          const SnackBar(content: Text('Switched station successfully')),
        );
        // Re-init queue to fetch new room and join it
        await _initQueue();
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          messenger.showSnackBar(
            SnackBar(content: Text('Failed to switch station: $e')),
          );
        }
      }
    }
  }

  Widget _buildFilePreviews() {
    if (_selectedFiles.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                'Attachments (${_selectedFiles.length})',
                style: TextStyle(
                  color: AppTheme.textPrimary.withValues(alpha: 0.9),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() {
                    _selectedFiles.clear();
                  });
                },
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Clear all'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 62,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _selectedFiles.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final file = _selectedFiles[index];
                final ext = file.extension?.toLowerCase() ?? '';
                final isImage = ['jpg', 'jpeg', 'png'].contains(ext);

                return Container(
                  width: 168,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.background.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: AppTheme.cardBorder),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.surface.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: isImage && file.path != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(file.path!),
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Icon(
                                ext == 'pdf'
                                    ? Icons.picture_as_pdf
                                    : ext == 'mp4' || ext == 'mov'
                                        ? Icons.videocam
                                        : Icons.insert_drive_file,
                                color: AppTheme.textSecondary,
                                size: 20,
                              ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              file.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatFileSize(file.size),
                              style: TextStyle(
                                color: AppTheme.textSecondary.withValues(alpha: 0.75),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _removeFile(index),
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.9),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.close,
                              size: 12, color: AppTheme.textPrimary),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    final hasContent = !_isUploading &&
        (_messageController.text.trim().isNotEmpty || _selectedFiles.isNotEmpty);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_replyToMessage != null) _buildReplyPreview(_replyToMessage!),
        _buildFilePreviews(),
        Container(
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          constraints: const BoxConstraints(
            minHeight: 54,
            maxHeight: 120,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.cardBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.85),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  padding: const EdgeInsets.all(0),
                  constraints: const BoxConstraints(),
                  icon: Icon(Icons.add, color: AppTheme.textPrimary, size: 20),
                  onPressed: _isUploading ? null : _pickFiles,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: 38,
                    maxHeight: 92,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.background.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppTheme.surface.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 24, minHeight: 24),
                        icon: Icon(
                          Icons.emoji_emotions_outlined,
                          size: 18,
                          color: AppTheme.textSecondary.withValues(alpha: 0.75),
                        ),
                        onPressed: _openEmojiPicker,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          focusNode: _focusNode,
                          minLines: 1,
                          maxLines: 4,
                          textAlignVertical: TextAlignVertical.center,
                          textCapitalization: TextCapitalization.sentences,
                          onChanged: _handleComposerChanged,
                          style:
                              TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 10,
                            ),
                            border: InputBorder.none,
                            hintText: _isUploading
                                ? 'Uploading attachments...'
                                : 'Type a message...',
                            hintStyle: TextStyle(
                              color: AppTheme.textPrimary.withValues(alpha: 0.45),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: hasContent
                      ? AppTheme.primaryGradient
                      : LinearGradient(
                          colors: [
                            AppTheme.cardBorder,
                            AppTheme.cardBorder,
                          ],
                        ),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: _isUploading
                      ? Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                              color: AppTheme.textPrimary, strokeWidth: 2),
                        )
                      : Icon(Icons.send_rounded,
                          color: hasContent ? Colors.white : AppTheme.textSecondary.withValues(alpha: 0.75),  // White is intentional: icon sits on accent-colored circle
                          size: 19),
                  onPressed: hasContent ? _sendMessage : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openEmojiPicker() async {
    _focusNode.unfocus();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.cardBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Done'),
                    ),
                  ],
                ),
                SizedBox(
                  height: 240,
                  child: GridView.builder(
                    itemCount: _emojiPalette.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 8,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                    ),
                    itemBuilder: (context, index) {
                      final emoji = _emojiPalette[index];
                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _insertEmoji(emoji, requestFocus: false),
                        child: Center(
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (mounted) _focusNode.requestFocus();
  }

  void _handleComposerChanged(String value) {
    setState(() {});
    final roomId = context.read<ChatProvider>().currentRoomId;
    if (roomId == null || value.trim().isEmpty) return;
    _typingDebounceTimer?.cancel();
    _typingDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      context.read<ChatProvider>().sendTyping(roomId);
    });
  }

  Widget _buildTypingIndicator(List<String> typingUsers) {
    final label = typingUsers.length == 1
        ? '${typingUsers.first} is typing...'
        : '${typingUsers.first} and others are typing...';
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        style: TextStyle(
          color: AppTheme.textPrimary.withValues(alpha: 0.62),
          fontSize: 11.5,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildReplyPreview(Message replyMessage) {
    final senderName = _isMessageFromCurrentUser(replyMessage) ? 'You' : replyMessage.sender.username;
    final preview = _pinnedPreviewText(replyMessage);

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 34,
            decoration: BoxDecoration(
              color: AppTheme.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Replying to $senderName',
                  style: TextStyle(
                    color: AppTheme.textPrimary.withValues(alpha: 0.82),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textPrimary.withValues(alpha: 0.68),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, color: AppTheme.textPrimary.withValues(alpha: 0.75), size: 18),
            onPressed: () {
              setState(() {
                _replyToMessage = null;
              });
            },
          ),
        ],
      ),
    );
  }

  bool _isMessageFromCurrentUser(Message message) {
    final currentUser = context.read<AuthProvider>().user;
    final sameUserId = currentUser?.id != null &&
        message.sender.id > 0 &&
        message.sender.id == currentUser!.id;
    final sameUsername = _normalizeUsername(currentUser?.username ?? '') ==
        _normalizeUsername(message.sender.username);
    return sameUserId || sameUsername;
  }

  void _setReplyMessage(Message message) {
    setState(() {
      _replyToMessage = message;
    });
    _focusNode.requestFocus();
    HapticFeedback.selectionClick();
  }

  void _insertEmoji(String emoji, {bool requestFocus = true}) {
    final oldText = _messageController.text;
    final selection = _messageController.selection;

    final start = selection.isValid ? selection.start : oldText.length;
    final end = selection.isValid ? selection.end : oldText.length;

    final newText = oldText.replaceRange(start, end, emoji);
    _messageController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );

    setState(() {});
    if (requestFocus) _focusNode.requestFocus();
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _copyMessage(Message message) async {
    final text = message.content.trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Message copied')),
    );
  }

  Future<void> _togglePinMessage(Message message) async {
    try {
      await context
          .read<AuthProvider>()
          .apiClient
          .post('/api/messages/${message.id}/pin/');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update pin: $e')),
      );
    }
  }

  Future<void> _deleteMessage(Message message) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Delete message'),
        content: const Text('Are you sure you want to delete this message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    if (shouldDelete != true) return;

    try {
      await context
          .read<AuthProvider>()
          .apiClient
          .delete('/api/messages/${message.id}/delete/');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete message: $e')),
      );
    }
  }

  Future<void> _editMessage(Message message) async {
    final updated = await showDialog<String>(
      context: context,
      builder: (ctx) => _EditMessageDialog(initialText: message.content),
    );
    if (!mounted) return;

    if (updated == null || updated.isEmpty || updated == message.content) {
      return;
    }

    try {
      await context.read<AuthProvider>().apiClient.patch(
            '/api/messages/${message.id}/edit/',
            body: {'content': updated},
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to edit message: $e')),
      );
    }
  }

  String _normalizeUsername(String value) {
    var normalized = value.trim().toLowerCase();
    if (normalized.startsWith('chat__')) {
      normalized = normalized.substring(6);
    } else if (normalized.startsWith('chat_')) {
      normalized = normalized.substring(5);
    }
    return normalized;
  }

  String _getDisplayName(String rawName) {
    String name = rawName;
    if (name.startsWith('chat__')) {
      name = name.substring(6);
    } else if (name.startsWith('chat_')) {
      name = name.substring(5);
    }

    if (name.isNotEmpty) {
      return name[0].toUpperCase() + name.substring(1);
    }
    return name;
  }

  String? _getUserTypeLabel(Room room) {
    final q = room.queueName?.toLowerCase() ?? '';
    if (q.contains('agent')) return 'AGENT';
    if (q.contains('player')) return 'PLAYER';
    if (q.contains('high roller')) return 'VIP';
    return null;
  }

  Color _getUserTypeColor(Room room) {
    final label = _getUserTypeLabel(room);
    switch (label) {
      case 'AGENT':
        return Colors.blueAccent;
      case 'PLAYER':
        return Colors.green;
      case 'VIP':
        return Colors.amber.shade700;
      default:
        return Colors.grey;
    }
  }
}

class _SwipeToReplyWrapper extends StatefulWidget {
  final bool isMe;
  final VoidCallback onReply;
  final Widget child;

  const _SwipeToReplyWrapper({
    super.key,
    required this.isMe,
    required this.onReply,
    required this.child,
  });

  @override
  State<_SwipeToReplyWrapper> createState() => _SwipeToReplyWrapperState();
}

class _SwipeToReplyWrapperState extends State<_SwipeToReplyWrapper> {
  static const double _maxOffset = 60;
  static const double _triggerOffset = 42;
  double _dx = 0;
  bool _triggered = false;

  bool _isReplyDirection(double deltaDx) {
    if (widget.isMe) {
      return deltaDx < 0;
    }
    return deltaDx > 0;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isReplyDirection(details.delta.dx)) {
      if (_dx != 0) {
        setState(() => _dx = 0);
      }
      return;
    }

    final next = _dx + details.delta.dx;
    final clamped = widget.isMe
        ? next.clamp(-_maxOffset, 0.0).toDouble()
        : next.clamp(0.0, _maxOffset).toDouble();

    if (clamped != _dx) {
      setState(() => _dx = clamped);
    }

    if (!_triggered && _dx.abs() >= _triggerOffset) {
      _triggered = true;
      HapticFeedback.lightImpact();
      widget.onReply();
    }
  }

  void _resetDrag() {
    if (_dx != 0) {
      setState(() => _dx = 0);
    }
    _triggered = false;
  }

  @override
  Widget build(BuildContext context) {
    final revealProgress = (_dx.abs() / _triggerOffset).clamp(0.0, 1.0);
    final showOnRight = widget.isMe;

    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          left: showOnRight ? null : 10,
          right: showOnRight ? 10 : null,
          child: Opacity(
            opacity: revealProgress * 0.9,
            child: Icon(
              Icons.reply_rounded,
              size: 18,
              color: AppTheme.accent.withValues(alpha: 0.9),
            ),
          ),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(_dx, 0, 0),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: (_) => _resetDrag(),
            onHorizontalDragCancel: _resetDrag,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Message message;
  final Message? replySourceMessage;
  final bool isStaff;
  final bool isMe;
  final bool isCurrentUserStaff;
  final bool showSender;
  final bool compactBottom;
  final bool showStatus;
  final bool isHighlighted;
  final ValueChanged<bool>? onMenuVisibilityChanged;
  final VoidCallback onCopy;
  final VoidCallback onPinToggle;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _MessageBubble({
    required this.message,
    this.replySourceMessage,
    required this.isStaff,
    required this.isMe,
    required this.isCurrentUserStaff,
    this.showSender = true,
    this.compactBottom = false,
    this.showStatus = false,
    this.isHighlighted = false,
    this.onMenuVisibilityChanged,
    required this.onCopy,
    required this.onPinToggle,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr = _getHumanReadableTime(message.timestamp.toLocal());
    final statusLabel = (isMe && showStatus)
        ? (message.isPending
            ? 'Sending'
            : (message.isRead ? 'Seen' : 'Sent'))
        : null;
    Color bubbleColor = AppTheme.surface;
    if (isStaff) {
      final staffColors = [
        AppTheme.primary,
        Colors.indigo,
        Colors.teal.shade700,
        Colors.deepOrange.shade700,
        Colors.brown.shade600,
        Colors.blueGrey.shade700,
      ];
      bubbleColor = staffColors[message.sender.id % staffColors.length];
    } else if (isMe) {
      // Give the current user's own bubbles the primary color so they
      // stand out and can safely use white text in any theme.
      bubbleColor = AppTheme.primary;
    }

    final isAlignedRight = isMe || (isStaff && isCurrentUserStaff);
    // Bubbles with a vibrant/dark color (staff or own primary) can use white text.
    // Incoming bubbles sit on the surface color and need theme-aware text.
    final hasDarkBubble = isStaff || isMe;
    final incomingBaseColor = AppTheme.surface.withValues(alpha: 0.9);
    final borderColor = isAlignedRight
        ? AppTheme.textPrimary.withValues(alpha: 0.14)
        : AppTheme.cardBorder;
    final effectiveBorderColor = isHighlighted
        ? AppTheme.accent.withValues(alpha: 0.9)
        : borderColor;
    // Bubbles with dark/vibrant backgrounds keep white text;
    // incoming bubbles on surface color adapt to the current theme.
    final bodyTextColor = hasDarkBubble
        ? Colors.white.withValues(alpha: 0.94)
        : AppTheme.textPrimary;
    // Sender name, timestamps, and read receipts render OUTSIDE the bubble
    // (on the screen background), so they must always be theme-aware.
    final metaTextColor = AppTheme.textSecondary;
    final senderTextColor = AppTheme.accent.withValues(alpha: 0.95);
    final baseRadius = AppTheme.radius;
    final bubbleRadius = BorderRadius.only(
      topLeft: Radius.circular(isAlignedRight ? baseRadius + 4 : baseRadius / 2),
      topRight: Radius.circular(isAlignedRight ? baseRadius / 2 : baseRadius + 4),
      bottomLeft: Radius.circular(compactBottom && !isAlignedRight ? baseRadius / 4 : baseRadius + 4),
      bottomRight: Radius.circular(compactBottom && isAlignedRight ? baseRadius / 4 : baseRadius + 4),
    );

    final attachmentType = message.attachment?.fileType ?? '';
    final isVisualAttachmentOnly = message.content.trim().isEmpty &&
        message.attachment != null &&
        (attachmentType.startsWith('image/') ||
            attachmentType.startsWith('video/'));

    final contentWidgets = <Widget>[
      if (message.isPinned)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Icon(
            Icons.push_pin,
            size: 13,
            color: Colors.amber.withValues(alpha: 0.95),
          ),
        ),
      if (message.isBroadcast)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.45)),
          ),
          child: const Text(
            'BROADCAST',
            style: TextStyle(
              color: Colors.amber,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
      if (message.replyToMessageId != null ||
          (message.replyToContent?.trim().isNotEmpty ?? false) ||
          (message.replyToSenderUsername?.trim().isNotEmpty ?? false))
        _buildReplyReference(bodyTextColor),
      if (message.content.isNotEmpty)
        _buildMessageContent(
          context,
          message.content,
          bodyTextColor,
          isDeleted: message.isDeleted,
        ),
      _buildAttachment(context),
    ];

    final bubbleBody = Align(
      alignment: isAlignedRight ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        child: Column(
          crossAxisAlignment:
              isAlignedRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showSender)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  isMe ? 'You' : message.sender.username,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: senderTextColor,
                    fontSize: 11,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            RawGestureDetector(
              gestures: {
                LongPressGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                        LongPressGestureRecognizer>(
                  () => LongPressGestureRecognizer(
                        duration: const Duration(milliseconds: 200),
                      ),
                  (instance) {
                    instance.onLongPressStart = (details) {
                      _showMessageActions(context, details.globalPosition);
                    };
                  },
                ),
              },
              child: Container(
                margin: EdgeInsets.only(bottom: compactBottom ? 2 : 8),
                padding: isVisualAttachmentOnly
                    ? EdgeInsets.zero
                    : const EdgeInsets.fromLTRB(12, 10, 12, 8),
                decoration: isVisualAttachmentOnly
                    ? null
                    : BoxDecoration(
                        color: AppTheme.visualStyle == VisualStyle.flat
                            ? (isAlignedRight ? bubbleColor.withValues(alpha: 0.85) : incomingBaseColor.withValues(alpha: 0.85))
                            : null,
                        gradient: (AppTheme.visualStyle == VisualStyle.card && !isVisualAttachmentOnly)
                            ? (isAlignedRight
                                ? LinearGradient(
                                    colors: [
                                      bubbleColor.withValues(alpha: 0.96),
                                      bubbleColor.withValues(alpha: 0.82),
                                    ],
                                    begin: Alignment.topRight,
                                    end: Alignment.bottomRight,
                                  )
                                : LinearGradient(
                                    colors: [
                                      incomingBaseColor.withValues(alpha: 0.94),
                                      incomingBaseColor.withValues(alpha: 0.86),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ))
                            : null,
                        border: Border.all(
                          color: effectiveBorderColor,
                          width: isHighlighted ? 1.3 : 1,
                        ),
                        borderRadius: bubbleRadius,
                        boxShadow: AppTheme.visualStyle == VisualStyle.card
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.14),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                                if (isHighlighted)
                                  BoxShadow(
                                    color: AppTheme.accent.withValues(alpha: 0.22),
                                    blurRadius: 16,
                                    offset: const Offset(0, 2),
                                  ),
                              ]
                            : null,
                      ),
                child: Column(
                  crossAxisAlignment: isAlignedRight
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: contentWidgets,
                ),
              ),
            ),
            if (message.isEdited)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Edited',
                  style: TextStyle(
                    color: metaTextColor,
                    fontSize: 10.5,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            if (statusLabel != null && compactBottom)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusLabel == 'Seen'
                        ? AppTheme.accent.withValues(alpha: 0.95)
                        : metaTextColor,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (!compactBottom)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (statusLabel != null) ...[
                        Text(
                          statusLabel,
                          style: TextStyle(
                            color: statusLabel == 'Seen'
                                ? AppTheme.accent.withValues(alpha: 0.95)
                                : metaTextColor,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Icon(
                        Icons.schedule_rounded,
                        size: 11,
                        color: metaTextColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        timeStr,
                        style: TextStyle(
                          color: metaTextColor,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
              ),
          ],
        ),
      ),
    );

    return bubbleBody;
  }

  static const String _postSharePrefix = 'POST_SHARE::';

  Widget _buildMessageContent(
    BuildContext context,
    String content,
    Color bodyTextColor, {
    bool isDeleted = false,
  }) {
    final sharedPost = _parseSharedPostPayload(content);
    if (sharedPost == null || isDeleted) {
      return _buildMessageContentText(content, bodyTextColor, isDeleted: isDeleted);
    }
    return _buildSharedPostPreview(context, sharedPost, bodyTextColor);
  }

  Map<String, dynamic>? _parseSharedPostPayload(String content) {
    if (!content.startsWith(_postSharePrefix)) return null;
    final raw = content.substring(_postSharePrefix.length).trim();
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      return null;
    }
    return null;
  }

  String _firstNonEmpty(List<dynamic> values, {String fallback = ''}) {
    for (final value in values) {
      final text = (value ?? '').toString().trim();
      if (text.isNotEmpty) return text;
    }
    return fallback;
  }

  String? _resolveSharedPostImageUrl(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    final base = ApiClient.baseUrl.endsWith('/')
        ? ApiClient.baseUrl.substring(0, ApiClient.baseUrl.length - 1)
        : ApiClient.baseUrl;
    final path = value.startsWith('/') ? value : '/$value';
    return '$base$path';
  }

  Future<void> _openSharedPost(
    BuildContext context,
    Map<String, dynamic> payload,
  ) async {
    final postIdRaw = payload['post_id'];
    final postId = postIdRaw is int
        ? postIdRaw
        : int.tryParse(postIdRaw?.toString() ?? '');
    if (postId == null) {
      final postUrl = payload['post_url']?.toString().trim() ?? '';
      if (postUrl.isNotEmpty) {
        await _launchUrl(postUrl);
      }
      return;
    }

    try {
      final auth = context.read<AuthProvider>();
      final response = await auth.apiClient.get('/api/posts/$postId/');
      Map<String, dynamic>? postJson;
      if (response is Map<String, dynamic>) {
        if (response['data'] is Map<String, dynamic>) {
          postJson = response['data'] as Map<String, dynamic>;
        } else {
          postJson = response;
        }
      }
      if (postJson == null) throw Exception('Unable to open shared post.');
      final post = Post.fromJson(postJson);
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PostDetailsScreen(post: post)),
      );
    } catch (_) {
      final postUrl = payload['post_url']?.toString().trim() ?? '';
      if (postUrl.isNotEmpty) {
        await _launchUrl(postUrl);
      }
    }
  }

  Widget _buildSharedPostPreview(
    BuildContext context,
    Map<String, dynamic> payload,
    Color bodyTextColor,
  ) {
    final title = _firstNonEmpty([
      payload['title'],
      payload['excerpt'],
      'Shared post',
    ]);
    final excerpt = _firstNonEmpty([payload['excerpt']]);
    final author = _firstNonEmpty([payload['author_username']]);
    final imageUrl = _resolveSharedPostImageUrl(payload['image_url']?.toString());

    return GestureDetector(
      onTap: () => _openSharedPost(context, payload),
      child: Container(
        margin: const EdgeInsets.only(top: 2, bottom: 2),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: bodyTextColor.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.article_outlined,
                  size: 14,
                  color: bodyTextColor.withValues(alpha: 0.85),
                ),
                const SizedBox(width: 6),
                Text(
                  'Shared Post',
                  style: TextStyle(
                    color: bodyTextColor.withValues(alpha: 0.88),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  imageUrl,
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            if (imageUrl != null) const SizedBox(height: 8),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: bodyTextColor,
                fontSize: 13.2,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            if (excerpt.isNotEmpty && excerpt != title) ...[
              const SizedBox(height: 4),
              Text(
                excerpt,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: bodyTextColor.withValues(alpha: 0.8),
                  fontSize: 12.2,
                  height: 1.3,
                ),
              ),
            ],
            if (author.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                'by $author',
                style: TextStyle(
                  color: bodyTextColor.withValues(alpha: 0.68),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMessageContentText(
    String content,
    Color bodyTextColor, {
    bool isDeleted = false,
  }) {
    final baseStyle = TextStyle(
      color: isDeleted ? bodyTextColor.withValues(alpha: 0.62) : bodyTextColor,
      fontSize: 15,
      height: 1.36,
      fontStyle: isDeleted ? FontStyle.italic : FontStyle.normal,
      fontWeight: isDeleted ? FontWeight.w400 : FontWeight.w500,
    );
    final linkStyle = baseStyle.copyWith(
      color: Colors.lightBlueAccent.shade100,
      decoration: TextDecoration.underline,
      decorationColor: Colors.lightBlueAccent.shade100,
      fontWeight: FontWeight.w500,
    );

    final regex = RegExp(r'((https?:\/\/|www\.)[^\s]+)', caseSensitive: false);
    final matches = regex.allMatches(content).toList();
    if (matches.isEmpty) {
      return Text(content, style: baseStyle);
    }

    final spans = <InlineSpan>[];
    int current = 0;

    for (final match in matches) {
      if (match.start > current) {
        spans.add(TextSpan(
          text: content.substring(current, match.start),
          style: baseStyle,
        ));
      }

      final rawLink = content.substring(match.start, match.end);
      final cleanedLink = rawLink.replaceAll(RegExp(r'[),.;!?]+$'), '');
      final trailing = rawLink.substring(cleanedLink.length);
      final linkForLaunch = cleanedLink.startsWith('http')
          ? cleanedLink
          : 'https://$cleanedLink';

      spans.add(
        TextSpan(
          text: cleanedLink,
          style: linkStyle,
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              _launchUrl(linkForLaunch);
            },
        ),
      );

      if (trailing.isNotEmpty) {
        spans.add(TextSpan(text: trailing, style: baseStyle));
      }

      current = match.end;
    }

    if (current < content.length) {
      spans.add(TextSpan(
        text: content.substring(current),
        style: baseStyle,
      ));
    }

    return RichText(text: TextSpan(children: spans));
  }

  Widget _buildReplyReference(Color bodyTextColor) {
    final sender = replySourceMessage?.sender.username ??
        message.replyToSenderUsername ??
        'Unknown';
    final content = replySourceMessage?.content.trim().isNotEmpty == true
        ? replySourceMessage!.content.trim()
        : (message.replyToContent?.trim().isNotEmpty == true
            ? message.replyToContent!.trim()
            : _attachmentSummary(replySourceMessage?.attachment?.fileType));

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 230),
      child: Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(7, 5, 7, 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(7),
        border: Border(
          left: BorderSide(
            color: AppTheme.accent.withValues(alpha: 0.95),
            width: 2.2,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            sender,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.accent.withValues(alpha: 0.95),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            content,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: bodyTextColor.withValues(alpha: 0.8),
              fontSize: 10.5,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    ),
    );
  }

  String _attachmentSummary(String? fileType) {
    if (fileType == null || fileType.isEmpty) return '[Original message]';
    if (fileType.startsWith('image/')) return '[Image]';
    if (fileType.startsWith('video/')) return '[Video]';
    return '[File]';
  }

  void _showMessageActions(BuildContext context, Offset globalPosition) {
    onMenuVisibilityChanged?.call(true);
    final attachment = message.attachment;
    final hasAttachment = attachment != null;
    String? attachmentUrl;
    String? attachmentFileType;
    String? attachmentFilename;
    if (attachment != null) {
      attachmentUrl = _resolveAttachmentUrl(attachment.file);
      attachmentFileType = attachment.fileType ?? 'unknown';
      attachmentFilename =
          attachment.filename ?? _deriveFilenameFromUrl(attachmentUrl);
    }

    final items = <PopupMenuEntry<String>>[
      const PopupMenuItem<String>(
        value: 'copy',
        child: Text('Copy'),
      ),
      PopupMenuItem<String>(
        value: 'pin',
        child: Text(message.isPinned ? 'Unpin' : 'Pin'),
      ),
      if (hasAttachment)
        const PopupMenuItem<String>(
          value: 'open_attachment',
          child: Text('Open'),
        ),
      if (hasAttachment)
        const PopupMenuItem<String>(
          value: 'download_attachment',
          child: Text('Download'),
        ),
    ];

    if (onEdit != null) {
      items.add(
        const PopupMenuItem<String>(
          value: 'edit',
          child: Text('Edit'),
        ),
      );
    }
    if (onDelete != null) {
      items.add(
        const PopupMenuItem<String>(
          value: 'delete',
          child: Text('Delete'),
        ),
      );
    }

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: items,
      color: AppTheme.surface,
    ).then((selected) {
      switch (selected) {
        case 'copy':
          onCopy();
          break;
        case 'pin':
          onPinToggle();
          break;
        case 'open_attachment':
          if (attachmentUrl != null && attachmentFileType != null) {
            _openAttachment(context, attachmentUrl, attachmentFileType);
          }
          break;
        case 'download_attachment':
          if (attachmentUrl != null && attachmentFilename != null) {
            _downloadAttachment(context, attachmentUrl, attachmentFilename);
          }
          break;
        case 'edit':
          onEdit?.call();
          break;
        case 'delete':
          onDelete?.call();
          break;
      }
    }).whenComplete(() {
      onMenuVisibilityChanged?.call(false);
    });
  }

  Widget _buildAttachment(BuildContext context) {
    if (message.attachment == null) return const SizedBox.shrink();

    final attachment = message.attachment!;
    final fileType = attachment.fileType ?? 'unknown';

    final fileUrl = _resolveAttachmentUrl(attachment.file);

    if (fileType.startsWith('image/')) {
      return GestureDetector(
        onTap: () => _showFullScreenImage(context, fileUrl),
        child: Container(
          margin: const EdgeInsets.only(top: 8, bottom: 4),
          constraints: const BoxConstraints(
            maxWidth: 200,
            maxHeight: 250,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.cardBorder),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              fileUrl,
              fit: BoxFit.contain,
              loadingBuilder: (BuildContext context, Widget child,
                  ImageChunkEvent? loadingProgress) {
                if (loadingProgress == null) return child;
                return Center(
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                        : null,
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) =>
                  Icon(Icons.broken_image, color: AppTheme.textSecondary.withValues(alpha: 0.75)),
            ),
          ),
        ),
      );
    } else if (fileType.startsWith('video/')) {
      return GestureDetector(
        onTap: () => _showFullScreenVideo(context, fileUrl),
        child: Stack(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              constraints: const BoxConstraints(maxWidth: 220),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _InlineVideoPreview(videoUrl: fileUrl),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Icon(Icons.play_circle_fill,
                      color: AppTheme.textPrimary, size: 48),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      return GestureDetector(
        onTap: () => _launchUrl(fileUrl),
        child: Container(
          margin: const EdgeInsets.only(top: 8, bottom: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.cardBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getFileIcon(fileType),
                color: AppTheme.textPrimary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  attachment.filename ?? 'Attachment',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    decoration: TextDecoration.underline,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  String _resolveAttachmentUrl(String filePath) {
    if (filePath.startsWith('http')) return filePath;
    final baseUrl = ApiClient.baseUrl.endsWith('/')
        ? ApiClient.baseUrl.substring(0, ApiClient.baseUrl.length - 1)
        : ApiClient.baseUrl;
    final imagePath = filePath.startsWith('/') ? filePath : '/$filePath';
    return '$baseUrl$imagePath';
  }

  void _openAttachment(BuildContext context, String fileUrl, String fileType) {
    if (fileType.startsWith('image/')) {
      _showFullScreenImage(context, fileUrl);
      return;
    }
    if (fileType.startsWith('video/')) {
      _showFullScreenVideo(context, fileUrl);
      return;
    }
    _launchUrl(fileUrl);
  }

  IconData _getFileIcon(String fileType) {
    if (fileType.startsWith('video/')) return Icons.videocam;
    if (fileType.startsWith('audio/')) return Icons.audiotrack;
    if (fileType.contains('pdf')) return Icons.picture_as_pdf;
    return Icons.insert_drive_file;
  }

  Future<void> _launchUrl(String url) async {
    FocusManager.instance.primaryFocus?.unfocus();

    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      debugPrint('Could not launch $url');
    }
  }

  Future<void> _downloadAttachment(
      BuildContext context, String url, String fileName) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      messenger.showSnackBar(
        const SnackBar(content: Text('Downloading file...')),
      );

      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('Failed to download file (${response.statusCode})');
      }

      final directory = await _resolveDownloadDirectory();
      final sanitized = _buildDownloadFilename(fileName, url);
      final destination = await _createUniqueFile(
          '${directory.path}${Platform.pathSeparator}$sanitized');

      await destination.writeAsBytes(response.bodyBytes, flush: true);

      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Saved: ${destination.path}')),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    }
  }

  Future<Directory> _resolveDownloadDirectory() async {
    if (Platform.isAndroid) {
      // Force public root downloads folder on Android.
      final dir = Directory('/storage/emulated/0/Download');
      await dir.create(recursive: true);

      final probe = File(
          '${dir.path}${Platform.pathSeparator}.write_probe_${DateTime.now().microsecondsSinceEpoch}');
      await probe.writeAsString('ok', flush: true);
      if (await probe.exists()) {
        await probe.delete();
      }
      return dir;
    }

    final downloadsDir = await getDownloadsDirectory();
    if (downloadsDir != null) {
      await downloadsDir.create(recursive: true);
      return downloadsDir;
    }
    throw Exception('Downloads directory is unavailable on this device');
  }

  Future<File> _createUniqueFile(String desiredPath) async {
    final file = File(desiredPath);
    if (!await file.exists()) return file;

    final separator = desiredPath.lastIndexOf('.');
    final hasExtension = separator > 0;
    final base = hasExtension ? desiredPath.substring(0, separator) : desiredPath;
    final ext = hasExtension ? desiredPath.substring(separator) : '';
    var counter = 1;

    while (true) {
      final candidate = File('${base}_$counter$ext');
      if (!await candidate.exists()) return candidate;
      counter++;
    }
  }

  String _sanitizeFilename(String name) {
    final cleaned = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
    if (cleaned.isEmpty) return 'attachment';
    return cleaned;
  }

  String _buildDownloadFilename(String rawName, String url) {
    String candidate = rawName.trim();

    // If backend sends a signed URL/path as "filename", strip it.
    if (candidate.contains('://') || candidate.contains('?') || candidate.contains('&')) {
      candidate = _deriveFilenameFromUrl(candidate);
    }
    if (candidate.isEmpty || candidate == 'attachment') {
      candidate = _deriveFilenameFromUrl(url);
    }

    candidate = _sanitizeFilename(candidate);

    // Preserve extension while capping length to avoid OS/path errors.
    const maxNameLength = 80;
    final dot = candidate.lastIndexOf('.');
    if (candidate.length > maxNameLength && dot > 0 && dot < candidate.length - 1) {
      final ext = candidate.substring(dot);
      final allowedBaseLen = (maxNameLength - ext.length).clamp(1, maxNameLength);
      candidate = '${candidate.substring(0, allowedBaseLen)}$ext';
    } else if (candidate.length > maxNameLength) {
      candidate = candidate.substring(0, maxNameLength);
    }

    return candidate;
  }

  String _deriveFilenameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final segment =
          uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'attachment';
      final decoded = Uri.decodeComponent(segment);
      return decoded.isEmpty ? 'attachment' : decoded;
    } catch (_) {
      return 'attachment';
    }
  }

  void _showFullScreenVideo(BuildContext context, String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _FullScreenVideoScreen(url: url),
      ),
    );
  }

  void _showFullScreenImage(BuildContext context, String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: IconThemeData(color: AppTheme.textPrimary),
            elevation: 0,
          ),
          body: Center(
            child: InteractiveViewer(
              panEnabled: true,
              boundaryMargin: const EdgeInsets.all(20),
              minScale: 0.5,
              maxScale: 4,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(child: CircularProgressIndicator());
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getHumanReadableTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inSeconds < 60) {
      return 'now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min ago';
    } else if (difference.inHours < 24) {
      if (difference.inHours == 1) {
        return '1 hour ago';
      }
      return '${difference.inHours} hours ago';
    } else {
      if (difference.inDays == 1) {
        return 'Yesterday ${DateFormat('jm').format(timestamp)}';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} days ago';
      } else {
        return DateFormat('MMM d, yyyy h:mm a').format(timestamp);
      }
    }
  }
}

class _EditMessageDialog extends StatefulWidget {
  final String initialText;

  const _EditMessageDialog({required this.initialText});

  @override
  State<_EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends State<_EditMessageDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Text('Edit message'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 1,
        maxLines: 4,
        style: TextStyle(color: AppTheme.textPrimary),
        decoration: const InputDecoration(
          hintText: 'Update message',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _InlineVideoPreview extends StatefulWidget {
  final String videoUrl;

  const _InlineVideoPreview({required this.videoUrl});

  @override
  State<_InlineVideoPreview> createState() => _InlineVideoPreviewState();
}

class _InlineVideoPreviewState extends State<_InlineVideoPreview>
    with AutomaticKeepAliveClientMixin<_InlineVideoPreview> {
  VideoPlayerController? _controller;
  Future<void>? _initializeFuture;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _controller = controller;
    _initializeFuture = controller.initialize();
  }

  @override
  void didUpdateWidget(covariant _InlineVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _controller?.dispose();
      final controller =
          VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      _controller = controller;
      _initializeFuture = controller.initialize();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final controller = _controller;
    if (controller == null) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Icon(Icons.videocam, color: AppTheme.textSecondary, size: 36),
        ),
      );
    }

    return FutureBuilder<void>(
      future: _initializeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 120,
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        if (snapshot.hasError || !controller.value.isInitialized) {
          return SizedBox(
            height: 120,
            child: Center(
              child: Icon(Icons.videocam, color: AppTheme.textSecondary, size: 36),
            ),
          );
        }

        final ratio = controller.value.aspectRatio <= 0
            ? 16 / 9
            : controller.value.aspectRatio;
        return AspectRatio(
          aspectRatio: ratio,
          child: VideoPlayer(controller),
        );
      },
    );
  }
}

class _SystemMessage extends StatelessWidget {
  final Message message;

  const _SystemMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    final cleanContent = message.content
        .replaceAll(RegExp(r'^System:\s*', caseSensitive: false), '');

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.textPrimary.withValues(
              alpha: 0.1), // var(--color-bg-secondary) approximation
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          cleanContent,
          style: TextStyle(
            color: AppTheme.textPrimary.withValues(
                alpha: 0.6), // var(--color-text-muted) approximation
            fontSize: 12, // ~0.75rem
            fontWeight: FontWeight.w400,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _FullScreenVideoScreen extends StatefulWidget {
  final String url;
  const _FullScreenVideoScreen({required this.url});

  @override
  State<_FullScreenVideoScreen> createState() => _FullScreenVideoScreenState();
}

class _FullScreenVideoScreenState extends State<_FullScreenVideoScreen> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    _videoPlayerController =
        VideoPlayerController.networkUrl(Uri.parse(widget.url));
    await _videoPlayerController.initialize();

    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController,
      autoPlay: true,
      looping: false,
      aspectRatio: _videoPlayerController.value.aspectRatio > 0
          ? _videoPlayerController.value.aspectRatio
          : 16 / 9,
      errorBuilder: (context, errorMessage) {
        return Center(
          child: Text(
            errorMessage,
            style: TextStyle(color: AppTheme.textPrimary),
          ),
        );
      },
    );
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppTheme.textPrimary),
      ),
      body: SafeArea(
        child: Center(
          child: _chewieController != null &&
                  _chewieController!.videoPlayerController.value.isInitialized
              ? Chewie(controller: _chewieController!)
              : const CircularProgressIndicator(),
        ),
      ),
    );
  }
}
