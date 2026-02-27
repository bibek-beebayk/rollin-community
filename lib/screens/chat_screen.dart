import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/room.dart';
import '../models/message.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../theme/app_theme.dart';
import '../api/api_client.dart';

import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dart:io';

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
  bool _isLoading = true;
  bool _isUploading = false;
  Room? _selectedChat;
  final List<PlatformFile> _selectedFiles = [];
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
    _messageController.dispose();
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
        chatProvider.sendMessage(chatProvider.currentRoomId!, text);
      }
      _messageController.clear();
    }

    _focusNode.requestFocus();
    Future.delayed(const Duration(milliseconds: 150), _scrollToBottom);
  }

  @override
  Widget build(BuildContext context) {
    // With unified dashboard, ChatScreen always shows the thread
    return _buildChatThread(context);
  }

  // _buildQueueView removed

  Widget _buildChatThread(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final currentUser = context.read<AuthProvider>().user;
    final isStaffUser = context.read<AuthProvider>().isStaff;
    final messages = chatProvider.messages;
    final unreadSwitchCount = chatProvider.activeChats.fold<int>(
      0,
      (sum, room) =>
          sum +
          ((_selectedChat != null && room.id == _selectedChat!.id)
              ? 0
              : room.unreadCount),
    );
    final titleText = isStaffUser
        ? _getDisplayName(_selectedChat?.name ?? 'Chat')
        : ((_selectedChat?.queueName != null &&
                !_selectedChat!.queueName!.startsWith('chat__'))
            ? _selectedChat!.queueName!
            : 'Support Station');

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: isStaffUser,
        leading: isStaffUser
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  Navigator.pop(context);
                },
              )
            : null,
        titleSpacing: 8,
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.primary.withValues(alpha: 0.9),
              child: Text(
                titleText.isNotEmpty ? titleText[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: Colors.white,
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
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
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
                            style: const TextStyle(
                              color: Colors.white,
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
                          color: Colors.white.withValues(alpha: 0.75),
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
          if (isStaffUser)
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
                          style: const TextStyle(
                            color: Colors.white,
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
              icon: const Icon(Icons.swap_horiz, color: Colors.white),
              tooltip: 'Switch Station',
              onPressed: () => _confirmSwitchStation(context),
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
              Expanded(
                child: Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.surface.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.06)),
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
                                        Colors.white.withValues(alpha: 0.28)),
                                const SizedBox(height: 10),
                                Text(
                                  'No messages yet',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Start the conversation below',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.5),
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
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
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

                            final isMe = message.sender.id == currentUser?.id;
                            final isStaff = message.sender.isStaff ||
                                (isMe && (currentUser?.isStaff ?? false));

                            bool showSender = true;
                            bool compactBottom = false;

                            if (reversedIndex > 0) {
                              final olderMessage = messages[reversedIndex - 1];
                              final diff = message.timestamp
                                  .difference(olderMessage.timestamp)
                                  .inMinutes;

                              if (olderMessage.sender.id == message.sender.id &&
                                  diff.abs() < 5) {
                                showSender = false;
                              }
                            }

                            if (reversedIndex < messages.length - 1) {
                              final newerMessage = messages[reversedIndex + 1];
                              final diff = newerMessage.timestamp
                                  .difference(message.timestamp)
                                  .inMinutes;
                              if (newerMessage.sender.id == message.sender.id &&
                                  diff.abs() < 5) {
                                compactBottom = true;
                              }
                            }

                            return _MessageBubble(
                              message: message,
                              isStaff: isStaff,
                              isMe: isMe,
                              isCurrentUserStaff: currentUser?.isStaff ?? false,
                              showSender: showSender,
                              compactBottom: compactBottom,
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
                        color: Colors.white.withValues(alpha: 0.08)),
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
                              color: Colors.white.withValues(alpha: 0.7))),
                    ],
                  ),
                ),
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
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
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
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Switch Conversation',
                    style: TextStyle(
                      color: Colors.white,
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
                      Divider(color: Colors.white.withValues(alpha: 0.08)),
                  itemBuilder: (context, index) {
                    final room = activeChats[index];
                    final isCurrent = _selectedChat?.id == room.id;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isCurrent
                            ? AppTheme.accent
                            : AppTheme.primary.withValues(alpha: 0.9),
                        child: Text(
                          _getDisplayName(room.name).isNotEmpty
                              ? _getDisplayName(room.name)[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: isCurrent ? Colors.black : Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        _getDisplayName(room.name),
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight:
                              isCurrent ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        room.queueName ?? 'ID: ${room.id}',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6)),
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
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          Icon(
                            isCurrent ? Icons.check_circle : Icons.chevron_right,
                            color: isCurrent
                                ? Colors.greenAccent
                                : Colors.white54,
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
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                  color: Colors.white.withValues(alpha: 0.85),
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
                        Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
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
                                color: Colors.white70,
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
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatFileSize(file.size),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55),
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
                          child: const Icon(Icons.close,
                              size: 12, color: Colors.white),
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
        _buildFilePreviews(),
        SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(18),
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                    icon: const Icon(Icons.add, color: Colors.white, size: 20),
                    onPressed: _isUploading ? null : _pickFiles,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 40),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.background.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06),
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
                            color: Colors.white.withValues(alpha: 0.55),
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
                            textCapitalization: TextCapitalization.sentences,
                            onChanged: (_) => setState(() {}),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              isCollapsed: true,
                              border: InputBorder.none,
                              hintText: _isUploading
                                  ? 'Uploading attachments...'
                                  : 'Type a message...',
                              hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
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
                              Colors.white.withValues(alpha: 0.12),
                              Colors.white.withValues(alpha: 0.08),
                            ],
                          ),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: _isUploading
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : Icon(Icons.send_rounded,
                            color: hasContent ? Colors.white : Colors.white54,
                            size: 19),
                    onPressed: hasContent ? _sendMessage : null,
                  ),
                ),
              ],
            ),
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
                        color: Colors.white24,
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

class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool isStaff;
  final bool isMe;
  final bool isCurrentUserStaff;
  final bool showSender;
  final bool compactBottom;

  const _MessageBubble({
    required this.message,
    required this.isStaff,
    required this.isMe,
    required this.isCurrentUserStaff,
    this.showSender = true,
    this.compactBottom = false,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr = _getHumanReadableTime(message.timestamp.toLocal());
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
    }

    final isAlignedRight = isMe || (isStaff && isCurrentUserStaff);
    final incomingBaseColor = AppTheme.surface.withValues(alpha: 0.9);
    final borderColor = isAlignedRight
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.white.withValues(alpha: 0.08);
    final bodyTextColor = Colors.white.withValues(alpha: 0.94);
    final metaTextColor = Colors.white.withValues(alpha: 0.64);
    final senderTextColor =
        isAlignedRight ? Colors.white : AppTheme.accent.withValues(alpha: 0.95);
    final bubbleRadius = BorderRadius.only(
      topLeft: Radius.circular(isAlignedRight ? 18 : 8),
      topRight: Radius.circular(isAlignedRight ? 8 : 18),
      bottomLeft: Radius.circular(compactBottom && !isAlignedRight ? 6 : 18),
      bottomRight: Radius.circular(compactBottom && isAlignedRight ? 6 : 18),
    );
    final attachmentType = message.attachment?.fileType ?? '';
    final isVisualAttachmentOnly = message.content.trim().isEmpty &&
        message.attachment != null &&
        (attachmentType.startsWith('image/') ||
            attachmentType.startsWith('video/'));

    final contentWidgets = <Widget>[
      if (message.content.isNotEmpty)
        Text(
          message.content,
          style: TextStyle(
            color: bodyTextColor,
            fontSize: 15,
            height: 1.36,
          ),
        ),
      _buildAttachment(context),
    ];

    return Align(
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
            Container(
              margin: EdgeInsets.only(bottom: compactBottom ? 2 : 8),
              padding: isVisualAttachmentOnly
                  ? EdgeInsets.zero
                  : const EdgeInsets.fromLTRB(12, 10, 12, 8),
              decoration: isVisualAttachmentOnly
                  ? null
                  : BoxDecoration(
                      gradient: isAlignedRight
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
                            ),
                      border: Border.all(color: borderColor),
                      borderRadius: bubbleRadius,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.14),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
              child: Column(
                crossAxisAlignment: isAlignedRight
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: contentWidgets,
              ),
            ),
            if (!compactBottom)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
  }

  Widget _buildAttachment(BuildContext context) {
    if (message.attachment == null) return const SizedBox.shrink();

    final attachment = message.attachment!;
    final fileType = attachment.fileType ?? 'unknown';

    // Use localhost for android emulator if needed, but here we use the URL from backend
    // If backend returns relative URL, prepend base URL
    String fileUrl = attachment.file;
    if (!fileUrl.startsWith('http')) {
      final baseUrl = ApiClient.baseUrl.endsWith('/')
          ? ApiClient.baseUrl.substring(0, ApiClient.baseUrl.length - 1)
          : ApiClient.baseUrl;
      final imagePath = fileUrl.startsWith('/') ? fileUrl : '/$fileUrl';
      fileUrl = '$baseUrl$imagePath';
    }

    if (fileType.startsWith('image/')) {
      return GestureDetector(
        onTap: () => _showFullScreenImage(context, fileUrl),
        child: Stack(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              constraints: const BoxConstraints(
                maxWidth: 200,
                maxHeight: 250,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
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
                      const Icon(Icons.broken_image, color: Colors.white54),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 6,
              child: _buildAttachmentMenuButton(
                context,
                fileUrl: fileUrl,
                filename: attachment.filename ?? 'image_${message.id}.jpg',
                onOpen: () => _showFullScreenImage(context, fileUrl),
              ),
            ),
          ],
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
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _InlineVideoPreview(videoUrl: fileUrl),
              ),
            ),
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Icon(Icons.play_circle_fill,
                      color: Colors.white, size: 48),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 6,
              child: _buildAttachmentMenuButton(
                context,
                fileUrl: fileUrl,
                filename: attachment.filename ?? 'video_${message.id}.mp4',
                onOpen: () => _showFullScreenVideo(context, fileUrl),
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
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getFileIcon(fileType),
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  attachment.filename ?? 'Attachment',
                  style: const TextStyle(
                    color: Colors.white,
                    decoration: TextDecoration.underline,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _buildAttachmentMenuButton(
                context,
                fileUrl: fileUrl,
                filename: attachment.filename ?? _deriveFilenameFromUrl(fileUrl),
                onOpen: () => _launchUrl(fileUrl),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildAttachmentMenuButton(
    BuildContext context, {
    required String fileUrl,
    required String filename,
    required VoidCallback onOpen,
  }) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        shape: BoxShape.circle,
      ),
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 16, color: Colors.white),
        padding: EdgeInsets.zero,
        splashRadius: 16,
        color: AppTheme.surface,
        onSelected: (value) {
          if (value == 'open') {
            onOpen();
          } else if (value == 'download') {
            _downloadAttachment(context, fileUrl, filename);
          }
        },
        itemBuilder: (ctx) => const [
          PopupMenuItem(
            value: 'open',
            child: Text('Open'),
          ),
          PopupMenuItem(
            value: 'download',
            child: Text('Download'),
          ),
        ],
      ),
    );
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
      final sanitized = _sanitizeFilename(fileName);
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
    Directory? dir = await getDownloadsDirectory();
    dir ??= await getExternalStorageDirectory();
    dir ??= await getApplicationDocumentsDirectory();
    await dir.create(recursive: true);
    return dir;
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

  String _deriveFilenameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final segment =
          uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'attachment';
      return segment.isEmpty ? 'attachment' : segment;
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
            iconTheme: const IconThemeData(color: Colors.white),
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
      return const SizedBox(
        height: 120,
        child: Center(
          child: Icon(Icons.videocam, color: Colors.white70, size: 36),
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
          return const SizedBox(
            height: 120,
            child: Center(
              child: Icon(Icons.videocam, color: Colors.white70, size: 36),
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
          color: Colors.white.withValues(
              alpha: 0.1), // var(--color-bg-secondary) approximation
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          cleanContent,
          style: TextStyle(
            color: Colors.white.withValues(
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
            style: const TextStyle(color: Colors.white),
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
        iconTheme: const IconThemeData(color: Colors.white),
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
