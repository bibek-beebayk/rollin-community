import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/room.dart';
import '../models/message.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_input.dart';
import '../api/api_client.dart';

import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';

class ChatScreen extends StatefulWidget {
  final Room room;

  const ChatScreen({super.key, required this.room});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _isLoading = true;
  bool _isUploading = false;
  Room? _selectedChat;
  List<PlatformFile> _selectedFiles = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initQueue());
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
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
      print('Error picking files: $e');
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

    if (mounted) setState(() => _isLoading = true);

    // Fetch active chats for EVERYONE to get latest room data (including canSwitchStation)
    try {
      await chatProvider.fetchActiveChats(authProvider.apiClient);
    } catch (e) {
      print('Error fetching active chats: $e');
    }

    if (!authProvider.isStaff) {
      // Find the room that matches widget.room (or default to it)
      // We need the one from provider because it has the latest flags
      final activeRoom = chatProvider.activeChats.firstWhere(
        (r) => r.id == widget.room.id,
        orElse: () => widget.room,
      );

      if (mounted) {
        setState(() {
          _selectedChat = activeRoom;
        });
      }
      await _openChatThread(activeRoom);
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _openChatThread(Room chatRoom) async {
    if (mounted) {
      setState(() {
        _selectedChat = chatRoom;
        _isLoading = true;
      });
    }

    final authProvider = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();
    final apiClient = authProvider.apiClient;

    if (apiClient.accessToken != null) {
      try {
        try {
          await apiClient.post('/api/rooms/${chatRoom.id}/join/');
        } catch (e) {
          // Ignore if already joined
        }

        chatProvider.connect(chatRoom.id, apiClient.accessToken!);

        await chatProvider.fetchMessages(chatRoom.id);

        if (mounted) {
          setState(() => _isLoading = false);
          Future.delayed(
              const Duration(milliseconds: 100), _scrollToBottomInstant);
        }
      } catch (e) {
        print('Error opening chat: $e');
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
            _scrollToBottomInstant(); // Jump instead of animate for snap effect on load
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

    // Upload files first
    if (_selectedFiles.isNotEmpty) {
      try {
        if (mounted) setState(() => _isUploading = true);

        // Upload sequentially to ensure order and error handling
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
          return; // Stop if upload fails
        }
      } finally {
        if (mounted) setState(() => _isUploading = false);
      }
    }

    // Send text if exists
    if (text.isNotEmpty) {
      chatProvider.sendMessage(text);
      _messageController.clear();
    }

    // Keep focus
    _focusNode.requestFocus();
    Future.delayed(const Duration(milliseconds: 150), _scrollToBottom);
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.read<AuthProvider>();
    if (_selectedChat == null && authProvider.isStaff) {
      return _buildQueueView(context);
    } else {
      return _buildChatThread(context);
    }
  }

  Widget _buildQueueView(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final queueChats = chatProvider.activeChats
        .where((chat) => chat.queue == widget.room.id)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.room.name} Queue'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _initQueue,
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : queueChats.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.inbox, size: 48, color: Colors.white24),
                      const SizedBox(height: 16),
                      Text(
                        'No active chats in this queue.',
                        style: TextStyle(color: Colors.white.withOpacity(0.6)),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: queueChats.length,
                  itemBuilder: (context, index) {
                    final chat = queueChats[index];
                    final displayName = chat.staff != null
                        ? (chat.name.isNotEmpty
                            ? chat.name
                            : "Chat #${chat.id}")
                        : chat.name;

                    return Card(
                      color: AppTheme.surface,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.primary,
                          child: Text(
                            displayName.isNotEmpty
                                ? displayName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(
                          displayName,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'Tap to open chat',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${chat.onlineCount}',
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 10)),
                            const SizedBox(width: 4),
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: chat.onlineCount > 0
                                    ? Colors.greenAccent
                                    : Colors.grey,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const Icon(Icons.chevron_right,
                                color: Colors.white54),
                          ],
                        ),
                        onTap: () => _openChatThread(chat),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildChatThread(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final currentUser = context.read<AuthProvider>().user;
    final messages = chatProvider.messages;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            final authProvider = context.read<AuthProvider>();
            if (authProvider.isStaff) {
              if (mounted) {
                setState(() {
                  _selectedChat = null;
                });
              }
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.read<AuthProvider>().isStaff
                  ? (_selectedChat?.name ?? 'Chat')
                  : ((_selectedChat?.queueName != null &&
                          !_selectedChat!.queueName!.startsWith('chat__'))
                      ? _selectedChat!.queueName!
                      : 'Support Station'),
            ),
            Text(
              chatProvider.isConnected ? 'Connected' : 'Connecting...',
              style: TextStyle(
                fontSize: 12,
                color: chatProvider.isConnected
                    ? Colors.greenAccent
                    : Colors.orangeAccent,
              ),
            ),
          ],
        ),
        actions: [
          if (!context.read<AuthProvider>().isStaff &&
              (_selectedChat?.canSwitchStation ?? false))
            IconButton(
              icon: const Icon(Icons.swap_horiz, color: Colors.white),
              tooltip: 'Switch Station',
              onPressed: () => _confirmSwitchStation(context),
            ),
          IconButton(
            icon: const Icon(Icons.check_circle_outline, color: Colors.green),
            tooltip: 'Close Ticket',
            onPressed: () => _confirmCloseTicket(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    // Reverse the index since we're using reverse: true
                    // messages is sorted Oldest -> Newest
                    // index 0 (bottom) should be Newest (last in list)
                    final reversedIndex = messages.length - 1 - index;
                    final message = messages[reversedIndex];

                    // Check for System Message
                    // Assuming system messages have type 'system' or 'notification'
                    // OR if content implies it (fallback)
                    final isSystemMessage = message.type == 'system' ||
                        message.type == 'notification' ||
                        message.sender.id == 0 || // Assuming 0 is system
                        message.content.startsWith('System:') ||
                        message.content
                            .toLowerCase()
                            .contains('switched station');

                    if (isSystemMessage) {
                      return _SystemMessage(message: message);
                    }

                    final isMe = message.sender.id == currentUser?.id;

                    // Grouping Logic
                    bool showSender = true;
                    bool compactBottom = false;

                    // Check Older Message (index + 1 in ListView)
                    if (reversedIndex > 0) {
                      final olderMessage = messages[reversedIndex - 1];
                      // Check if same sender and time diff < 5 mins
                      final diff = message.timestamp
                          .difference(olderMessage.timestamp)
                          .inMinutes;

                      if (olderMessage.sender.id == message.sender.id &&
                          diff.abs() < 5) {
                        showSender = false;
                      }
                    }

                    // Check Newer Message (index - 1 in ListView)
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
                      isMe: isMe,
                      showSender: showSender,
                      compactBottom: compactBottom,
                    );
                  },
                ),
              ),
              if (messages.isEmpty && !_isLoading)
                Center(
                  child: Text(
                    'No messages yet',
                    style: TextStyle(color: Colors.white.withOpacity(0.5)),
                  ),
                ),
              if (_isUploading)
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  color: AppTheme.surface,
                  child: Row(
                    children: [
                      const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 8),
                      Text('Uploading...',
                          style:
                              TextStyle(color: Colors.white.withOpacity(0.7))),
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
    );
  }

  Future<void> _confirmCloseTicket(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close Ticket?'),
        content: const Text(
            'Are you sure you want to close this support ticket? This specific chat room will be archived.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Close Ticket'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted && _selectedChat != null) {
      try {
        final api = context.read<AuthProvider>().apiClient;
        await api.post('/api/rooms/${_selectedChat!.id}/close/');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ticket closed successfully')),
          );
          // Refresh queue/list
          await _initQueue();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to close ticket: $e')),
          );
        }
      }
    }
  }

  Future<void> _confirmSwitchStation(BuildContext context) async {
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
      if (mounted) setState(() => _isLoading = true);
      try {
        final api = context.read<AuthProvider>().apiClient;
        await api.post('/api/rooms/switch-station/');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Switched station successfully')),
          );
          // Re-init queue to fetch new room and join it
          await _initQueue();
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to switch station: $e')),
          );
        }
      }
    }
  }

  Widget _buildFilePreviews() {
    if (_selectedFiles.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppTheme.surface,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedFiles.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final file = _selectedFiles[index];
          final isImage =
              ['jpg', 'jpeg', 'png'].contains(file.extension?.toLowerCase());

          return Stack(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: isImage && file.path != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(file.path!),
                          fit: BoxFit.cover,
                        ),
                      )
                    : const Center(
                        child: Icon(Icons.insert_drive_file,
                            color: Colors.white70, size: 24),
                      ),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: GestureDetector(
                  onTap: () => _removeFile(index),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.close, size: 12, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInputArea() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildFilePreviews(),
        SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              border:
                  Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file, color: Colors.white70),
                  onPressed: _pickFiles,
                ),
                Expanded(
                  child: CustomInput(
                    hintText: 'Type a message...',
                    controller: _messageController,
                    focusNode: _focusNode,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: _isUploading
                        ? const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: _isUploading ? null : _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final bool showSender;
  final bool compactBottom;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    this.showSender = true,
    this.compactBottom = false,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('jm').format(message.timestamp.toLocal());

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(bottom: compactBottom ? 2 : 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? AppTheme.primary : AppTheme.surface,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(showSender && !isMe ? 16 : 4),
            topRight: Radius.circular(showSender && isMe ? 16 : 4),
            bottomLeft: Radius.circular(compactBottom && !isMe ? 4 : 16),
            bottomRight: Radius.circular(compactBottom && isMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isMe && showSender)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  message.sender.username,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accent,
                    fontSize: 12,
                  ),
                ),
              ),
            if (message.content.isNotEmpty)
              Text(
                message.content,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            _buildAttachment(context),
            if (!compactBottom) ...[
              const SizedBox(height: 4),
              Text(
                timeStr,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 10,
                ),
              ),
            ],
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
      fileUrl = '${ApiClient.baseUrl}$fileUrl';
    }

    if (fileType.startsWith('image/')) {
      return GestureDetector(
        onTap: () => _launchUrl(fileUrl),
        child: Container(
          margin: const EdgeInsets.only(top: 8, bottom: 4),
          constraints: const BoxConstraints(
            maxWidth: 200,
            maxHeight: 250,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
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
    } else {
      return GestureDetector(
        onTap: () => _launchUrl(fileUrl),
        child: Container(
          margin: const EdgeInsets.only(top: 8, bottom: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
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

  IconData _getFileIcon(String fileType) {
    if (fileType.startsWith('video/')) return Icons.videocam;
    if (fileType.startsWith('audio/')) return Icons.audiotrack;
    if (fileType.contains('pdf')) return Icons.picture_as_pdf;
    return Icons.insert_drive_file;
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      print('Could not launch $url');
    }
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
          color: Colors.white
              .withOpacity(0.1), // var(--color-bg-secondary) approximation
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          cleanContent,
          style: TextStyle(
            color: Colors.white
                .withOpacity(0.6), // var(--color-text-muted) approximation
            fontSize: 12, // ~0.75rem
            fontWeight: FontWeight.w400,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
