import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/room.dart';
import '../models/message.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_input.dart';

class ChatScreen extends StatefulWidget {
  final Room room; // This is the SUPPORT ROOM (Queue)

  const ChatScreen({super.key, required this.room});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = true;
  Room? _selectedChat; // The specific Chat Session

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initQueue());
  }

  Future<void> _initQueue() async {
    final chatProvider = context.read<ChatProvider>();
    final authProvider = context.read<AuthProvider>();

    setState(() => _isLoading = true);

    // Fetch active chats to populate the queue list
    try {
      await chatProvider.fetchActiveChats(authProvider.apiClient);
    } catch (e) {
      print('Error fetching active chats: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openChatThread(Room chatRoom) async {
    setState(() {
      _selectedChat = chatRoom;
      _isLoading = true;
    });

    final authProvider = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();
    final apiClient = authProvider.apiClient;

    if (apiClient.accessToken != null) {
      // 1. Join request (ensure access to this specific chat)
      try {
        await apiClient.post('/api/rooms/${chatRoom.id}/join/');
      } catch (e) {
        // Ignore if already joined
      }

      // 2. Connect specific Chat ID
      chatProvider.connect(chatRoom.id, apiClient.accessToken!);

      // 3. Fetch History
      try {
        final data = await apiClient.get(
          '/api/rooms/${chatRoom.id}/messages/',
        );

        List<dynamic> jsonList = [];
        if (data is Map<String, dynamic>) {
          if (data.containsKey('results')) {
            jsonList = data['results'];
          } else if (data.containsKey('data')) {
            jsonList = data['data'];
          }
        } else if (data is List) {
          jsonList = data;
        }

        final messages = jsonList.map((j) => Message.fromJson(j)).toList();
        chatProvider.setHistory(messages);

        // Scroll to bottom after load
        Future.delayed(const Duration(milliseconds: 300), _scrollToBottom);
      } catch (e) {
        print('Error fetching history: $e');
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    context.read<ChatProvider>().sendMessage(text);
    _messageController.clear();
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    // Optional: Disconnect WS when leaving screen?
    // context.read<ChatProvider>().disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedChat == null) {
      return _buildQueueView(context);
    } else {
      return _buildChatThread(context);
    }
  }

  // --- QUEUE VIEW (List of active chats in this support room) ---
  Widget _buildQueueView(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();

    // Filter active chats that belong to this Support Room (Queue)
    // Assuming Room model has 'queue' field matching SupportRoom ID
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
                    // Use client name if available, else generic name
                    final displayName = chat.staff != null
                        ? (chat.name.isNotEmpty
                            ? chat.name
                            : "Chat #${chat.id}")
                        // Maybe use a 'client' field if Room has it?
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

  // --- THREAD VIEW ---
  Widget _buildChatThread(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final currentUser = context.read<AuthProvider>().user;
    final messages = chatProvider.messages;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // Disconnect or just go back?
            // Better to stay connected if we want to "minimize" but for now let's just go back
            // chatProvider.disconnect(); // Optional
            setState(() {
              _selectedChat = null;
              // Clear messages to avoid flash when opening another
              // chatProvider.messages.clear(); // Provider handles this on connect
            });
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_selectedChat?.name ?? 'Chat'),
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
          IconButton(
            icon: const Icon(Icons.check_circle_outline, color: Colors.green),
            tooltip: 'Close Ticket',
            onPressed: () => _confirmCloseTicket(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
                final isMe = message.sender.id == currentUser?.id;
                return _MessageBubble(message: message, isMe: isMe);
              },
            ),
          ),
          _buildInputArea(),
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
            'This will resolve the support request and remove it from your active list.'),
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
          // Close thread and modify UI
          setState(() {
            _selectedChat = null;
          });
          // Refresh queue
          _initQueue();
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

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      child: Row(
        children: [
          Expanded(
            child: CustomInput(
              hintText: 'Type a message...',
              controller: _messageController,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: const BoxDecoration(
              gradient: AppTheme.primaryGradient,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white),
              onPressed: _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;

  const _MessageBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('jm').format(message.timestamp.toLocal());

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? AppTheme.primary : AppTheme.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft:
                isMe ? const Radius.circular(16) : const Radius.circular(4),
            bottomRight:
                isMe ? const Radius.circular(4) : const Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe)
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
            Text(
              message.content,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              timeStr,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
