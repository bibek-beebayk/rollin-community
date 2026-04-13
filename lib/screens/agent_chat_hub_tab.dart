import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/room.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../theme/app_theme.dart';
import 'chat_screen.dart';

class AgentChatHubTab extends StatefulWidget {
  const AgentChatHubTab({super.key});

  @override
  State<AgentChatHubTab> createState() => _AgentChatHubTabState();
}

class _AgentChatHubTabState extends State<AgentChatHubTab> {
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedFilter = 'all';

  @override
  void initState() {
    super.initState();
    // Hub is a list view, not an opened conversation.
    // Clear route-open state and reset any stale current room pointer so
    // unread counters can increment correctly on list items.
    final chatProvider = context.read<ChatProvider>();
    chatProvider.setRouteChatOpen(false);
    final currentRoomId = chatProvider.currentRoomId;
    if (currentRoomId != null) {
      chatProvider.disconnectRoom(currentRoomId);
    }
    _loadChats();
  }

  Future<void> _loadChats() async {
    final chatProvider = context.read<ChatProvider>();
    final authProvider = context.read<AuthProvider>();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await chatProvider.fetchActiveChats(authProvider.apiClient);

      final hasSupport = chatProvider.activeChats.any((r) => r.roomType == 'support');
      if (!hasSupport) {
        await chatProvider.joinSupportRoom(authProvider.apiClient);
        await chatProvider.fetchActiveChats(authProvider.apiClient);
      }
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _titleForRoom(Room room) {
    if (room.roomType == 'support') return 'Support Chat';
    if (room.roomType == 'direct_agent' && room.counterpart != null) {
      return room.counterpart!.username;
    }
    if (room.queueName != null && room.queueName!.isNotEmpty) {
      return room.queueName!;
    }
    return room.name;
  }

  String _subtitleForRoom(Room room, String? userType) {
    if (room.roomType == 'support') return 'Primary support channel';
    if (room.roomType == 'direct_agent') {
      return userType == 'agent' ? 'Direct player chat' : 'Direct agent chat';
    }
    return 'Room #${room.id}';
  }

  Future<void> _openChat(Room room) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatScreen(room: room)),
    );
    if (!mounted) return;
    // Back on chat hub: ensure we're not still flagged as viewing this room.
    final chatProvider = context.read<ChatProvider>();
    if (chatProvider.currentRoomId == room.id) {
      chatProvider.disconnectRoom(room.id);
    }
    await _loadChats();
  }

  Widget _unreadBadge(int count) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.redAccent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  bool _needsReply(Room room, int? currentUserId) {
    if (currentUserId == null) return false;
    final senderId = room.lastMessageSenderId;
    if (senderId == null) return false;
    return senderId != currentUserId;
  }

  int _compareNullableDateDesc(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }

  List<Room> _buildPrioritizedRooms(
    List<Room> rooms, {
    required String? userType,
    required int? currentUserId,
  }) {
    final copied = [...rooms];
    if (userType == 'agent') {
      copied.sort((a, b) {
        final aNeedsReply = _needsReply(a, currentUserId);
        final bNeedsReply = _needsReply(b, currentUserId);
        if (aNeedsReply != bNeedsReply) return aNeedsReply ? -1 : 1;

        final unreadCompare = b.unreadCount.compareTo(a.unreadCount);
        if (unreadCompare != 0) return unreadCompare;

        return _compareNullableDateDesc(a.lastActivity, b.lastActivity);
      });
    } else {
      copied.sort((a, b) {
        final unreadCompare = b.unreadCount.compareTo(a.unreadCount);
        if (unreadCompare != 0) return unreadCompare;
        return _compareNullableDateDesc(a.lastActivity, b.lastActivity);
      });
    }

    if (_selectedFilter == 'needs_reply') {
      return copied
          .where((r) => _needsReply(r, currentUserId))
          .toList(growable: false);
    }
    if (_selectedFilter == 'unread') {
      return copied.where((r) => r.unreadCount > 0).toList(growable: false);
    }
    return copied;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadChats,
          child: Consumer<ChatProvider>(
            builder: (context, chatProvider, _) {
              final auth = context.read<AuthProvider>();
              final userType = auth.user?.userType;
              final currentUserId = auth.user?.id;
              final rooms = chatProvider.activeChats;
              Room? supportRoom;
              for (final room in rooms) {
                if (room.roomType == 'support') {
                  supportRoom = room;
                  break;
                }
              }
              final otherRoomsRaw = rooms.where((r) => r.roomType != 'support').toList();
              final otherRooms = _buildPrioritizedRooms(
                otherRoomsRaw,
                userType: userType,
                currentUserId: currentUserId,
              );

              if (_isLoading) {
                return const Center(
                  child: CircularProgressIndicator(color: AppTheme.accent),
                );
              }

              if (_errorMessage != null) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  children: [
                    const SizedBox(height: 120),
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 44),
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: OutlinedButton(
                        onPressed: _loadChats,
                        child: const Text('Retry'),
                      ),
                    ),
                  ],
                );
              }

              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                children: [
                  const Text(
                    'Chats',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (supportRoom != null)
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppTheme.accent.withValues(alpha: 0.7),
                          width: 1.2,
                        ),
                      ),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: AppTheme.accent,
                          child: Icon(Icons.support_agent, color: Colors.black),
                        ),
                        title: Text(
                          _titleForRoom(supportRoom),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          _subtitleForRoom(supportRoom, userType),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                        trailing: _unreadBadge(supportRoom.unreadCount),
                        onTap: () => _openChat(supportRoom!),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surface.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: const Text(
                        'Support chat is not available right now.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        userType == 'agent' ? 'Prioritized Chats' : 'Other Chats',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (userType == 'agent')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.orangeAccent.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.orangeAccent.withValues(alpha: 0.55),
                            ),
                          ),
                          child: const Text(
                            'Needs reply first',
                            style: TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (userType == 'agent') ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('All'),
                          labelStyle: TextStyle(
                            color: _selectedFilter == 'all'
                                ? Colors.black
                                : Colors.white.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
                          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                          shape: const StadiumBorder(),
                          side: BorderSide(
                            color: _selectedFilter == 'all'
                                ? AppTheme.accent.withValues(alpha: 0.9)
                                : Colors.white.withValues(alpha: 0.2),
                          ),
                          backgroundColor: Colors.white.withValues(alpha: 0.06),
                          selectedColor: AppTheme.accent,
                          selected: _selectedFilter == 'all',
                          onSelected: (_) => setState(() => _selectedFilter = 'all'),
                        ),
                        ChoiceChip(
                          label: const Text('Needs Reply'),
                          labelStyle: TextStyle(
                            color: _selectedFilter == 'needs_reply'
                                ? Colors.black
                                : Colors.white.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
                          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                          shape: const StadiumBorder(),
                          side: BorderSide(
                            color: _selectedFilter == 'needs_reply'
                                ? AppTheme.accent.withValues(alpha: 0.9)
                                : Colors.white.withValues(alpha: 0.2),
                          ),
                          backgroundColor: Colors.white.withValues(alpha: 0.06),
                          selectedColor: AppTheme.accent,
                          selected: _selectedFilter == 'needs_reply',
                          onSelected: (_) =>
                              setState(() => _selectedFilter = 'needs_reply'),
                        ),
                        ChoiceChip(
                          label: const Text('Unread'),
                          labelStyle: TextStyle(
                            color: _selectedFilter == 'unread'
                                ? Colors.black
                                : Colors.white.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
                          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                          shape: const StadiumBorder(),
                          side: BorderSide(
                            color: _selectedFilter == 'unread'
                                ? AppTheme.accent.withValues(alpha: 0.9)
                                : Colors.white.withValues(alpha: 0.2),
                          ),
                          backgroundColor: Colors.white.withValues(alpha: 0.06),
                          selectedColor: AppTheme.accent,
                          selected: _selectedFilter == 'unread',
                          onSelected: (_) => setState(() => _selectedFilter = 'unread'),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (otherRooms.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surface.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Text(
                        'No other chats available.',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
                      ),
                    )
                  else
                    ...otherRooms.map(
                      (room) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.surface.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.primary.withValues(alpha: 0.9),
                            child: Text(
                              _titleForRoom(room).isNotEmpty
                                  ? _titleForRoom(room)[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          title: Text(
                            _titleForRoom(room),
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            _needsReply(room, currentUserId)
                                ? '${_subtitleForRoom(room, userType)} • Needs reply'
                                : _subtitleForRoom(room, userType),
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
                          ),
                          trailing: _unreadBadge(room.unreadCount),
                          onTap: () => _openChat(room),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
