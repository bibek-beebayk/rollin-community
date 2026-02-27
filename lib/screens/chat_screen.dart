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
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
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
  final List<PlatformFile> _selectedFiles = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initQueue());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    debugPrint('DEBUG: ChatScreen dispose called');
    // REMOVED _chatProvider.disconnect() to persist connection across pushes

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

  Future<void> _openChatThread(Room chatRoom,
      {bool isAlreadyLoaded = false}) async {
    if (mounted) {
      setState(() {
        _selectedChat = chatRoom;
        if (!isAlreadyLoaded) {
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
          await chatProvider.fetchMessages(chatRoom.id);
          if (mounted) {
            setState(() => _isLoading = false);
            Future.delayed(
                const Duration(milliseconds: 100), _scrollToBottomInstant);
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
    final messages = chatProvider.messages;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: context.read<AuthProvider>().isStaff,
        leading: context.read<AuthProvider>().isStaff
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  Navigator.pop(context);
                },
              )
            : null,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    context.read<AuthProvider>().isStaff
                        ? _getDisplayName(_selectedChat?.name ?? 'Chat')
                        : ((_selectedChat?.queueName != null &&
                                !_selectedChat!.queueName!.startsWith('chat__'))
                            ? _selectedChat!.queueName!
                            : 'Support Station'),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (context.read<AuthProvider>().isStaff &&
                    _selectedChat != null &&
                    _getUserTypeLabel(_selectedChat!) != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getUserTypeColor(_selectedChat!),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: Text(
                      _getUserTypeLabel(_selectedChat!)!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
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
                    final isStaff = message.sender.isStaff ||
                        (isMe && (currentUser?.isStaff ?? false));

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
                      isStaff: isStaff,
                      isMe: isMe,
                      isCurrentUserStaff: currentUser?.isStaff ?? false,
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
                    style:
                        TextStyle(color: Colors.white.withValues(alpha: 0.5)),
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
    );
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

        if (!mounted) return;

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
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.2)),
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
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
                const SizedBox(width: 8),
                Container(
                  width: 38,
                  height: 38,
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

    // Generate a consistent color for a specific staff member based on their ID
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
      // Use modulo to cycle through colors based on staff ID
      bubbleColor = staffColors[message.sender.id % staffColors.length];
    } else {
      // Player / Agent color
      bubbleColor = AppTheme.surface;
    }

    final bool isAlignedRight = isMe || (isStaff && isCurrentUserStaff);

    return Align(
      alignment: isAlignedRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(bottom: compactBottom ? 2 : 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(showSender && !isAlignedRight ? 16 : 4),
            topRight: Radius.circular(showSender && isAlignedRight ? 16 : 4),
            bottomLeft:
                Radius.circular(compactBottom && !isAlignedRight ? 4 : 16),
            bottomRight:
                Radius.circular(compactBottom && isAlignedRight ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showSender)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  isMe ? 'You' : message.sender.username,
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
                  color: Colors.white.withValues(alpha: 0.5),
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
      final baseUrl = ApiClient.baseUrl.endsWith('/')
          ? ApiClient.baseUrl.substring(0, ApiClient.baseUrl.length - 1)
          : ApiClient.baseUrl;
      final imagePath = fileUrl.startsWith('/') ? fileUrl : '/$fileUrl';
      fileUrl = '$baseUrl$imagePath';
    }

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
        child: Container(
          margin: const EdgeInsets.only(top: 8, bottom: 4),
          constraints: const BoxConstraints(
            maxWidth: 200,
            maxHeight: 150,
          ),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: const Center(
            child:
                Icon(Icons.play_circle_outline, color: Colors.white, size: 48),
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
      debugPrint('Could not launch $url');
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
