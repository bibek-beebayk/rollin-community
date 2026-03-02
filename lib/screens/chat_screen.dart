import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/room.dart';
import '../models/message.dart';
import '../models/user.dart';
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
import 'package:flutter/services.dart';
import 'dart:io';
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
    final titleText = isStaffUser
        ? _getDisplayName(_selectedChat?.name ?? 'Chat')
        : ((_selectedChat?.queueName != null &&
                !_selectedChat!.queueName!.startsWith('chat__'))
            ? _selectedChat!.queueName!
            : 'Support Station');
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

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: isStaffUser,
        leading: isStaffUser
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  context.read<ChatProvider>().setRouteChatOpen(false);
                  context.read<ChatProvider>().setChatTabActive(false);
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
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                        color: Colors.white.withValues(alpha: 0.88),
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
                    color: Colors.white.withValues(alpha: 0.72),
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
                        color: Colors.white.withValues(alpha: 0.08),
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
                            color: Colors.white.withValues(alpha: 0.88),
                            fontSize: 12,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('MMM d, h:mm a')
                              .format(message.timestamp.toLocal()),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
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
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                  constraints: const BoxConstraints(
                    minHeight: 38,
                    maxHeight: 92,
                  ),
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
                          textAlignVertical: TextAlignVertical.center,
                          textCapitalization: TextCapitalization.sentences,
                          onChanged: _handleComposerChanged,
                          style:
                              const TextStyle(color: Colors.white, fontSize: 14),
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
          color: Colors.white.withValues(alpha: 0.62),
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
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
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
                    color: Colors.white.withValues(alpha: 0.82),
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
                    color: Colors.white.withValues(alpha: 0.68),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, color: Colors.white.withValues(alpha: 0.75), size: 18),
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
    }

    final isAlignedRight = isMe || (isStaff && isCurrentUserStaff);
    final incomingBaseColor = AppTheme.surface.withValues(alpha: 0.9);
    final borderColor = isAlignedRight
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.white.withValues(alpha: 0.08);
    final effectiveBorderColor = isHighlighted
        ? AppTheme.accent.withValues(alpha: 0.9)
        : borderColor;
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
      if (message.isPinned)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Icon(
            Icons.push_pin,
            size: 13,
            color: Colors.amber.withValues(alpha: 0.95),
          ),
        ),
      if (message.replyToMessageId != null ||
          (message.replyToContent?.trim().isNotEmpty ?? false) ||
          (message.replyToSenderUsername?.trim().isNotEmpty ?? false))
        _buildReplyReference(bodyTextColor),
      if (message.content.isNotEmpty)
        _buildMessageContentText(
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
                        border: Border.all(
                          color: effectiveBorderColor,
                          width: isHighlighted ? 1.3 : 1,
                        ),
                        borderRadius: bubbleRadius,
                        boxShadow: [
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
            // ignore: use_build_context_synchronously
            _openAttachment(context, attachmentUrl, attachmentFileType);
          }
          break;
        case 'download_attachment':
          if (attachmentUrl != null && attachmentFilename != null) {
            // ignore: use_build_context_synchronously
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
        style: const TextStyle(color: Colors.white),
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
