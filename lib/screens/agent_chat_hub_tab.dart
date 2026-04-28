import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/room.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../theme/app_theme.dart';
import 'chat_screen.dart';
import 'agent_search_screen.dart';

class AgentChatHubTab extends StatefulWidget {
  const AgentChatHubTab({super.key});

  @override
  State<AgentChatHubTab> createState() => _AgentChatHubTabState();
}

class _AgentChatHubTabState extends State<AgentChatHubTab> {
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedFilter = 'all';
  int _pendingGroupRequests = 0;

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
    final isAgentUser = authProvider.user?.isAgent ?? false;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await chatProvider.fetchActiveChats(authProvider.apiClient);
      if (isAgentUser) {
        final requests =
            await chatProvider.fetchManagedGroupJoinRequests(authProvider.apiClient);
        _pendingGroupRequests = requests.length;
      } else {
        _pendingGroupRequests = 0;
      }

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
    if (room.roomType == 'group') {
      return '${room.groupMemberCount} members';
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

  Future<void> _showCreateGroupDialog() async {
    final authProvider = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    final payload = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Create Group', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Group name',
                hintStyle: TextStyle(color: Colors.white54),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descriptionController,
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Description (optional)',
                hintStyle: TextStyle(color: Colors.white54),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, {
              'name': nameController.text.trim(),
              'description': descriptionController.text.trim(),
            }),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (payload == null || (payload['name'] ?? '').isEmpty) return;
    try {
      final room = await chatProvider.createGroup(
        authProvider.apiClient,
        name: payload['name']!,
        description: payload['description'] ?? '',
      );
      if (!mounted) return;
      await _loadChats();
      await _openChat(room);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    }
  }

  Future<void> _showGroupDiscoveryDialog() async {
    final authProvider = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();
    final queryController = TextEditingController();
    List<Map<String, dynamic>> groups = [];
    bool loading = true;

    Future<void> load({String query = ''}) async {
      groups = await chatProvider.discoverGroups(authProvider.apiClient, query: query);
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          if (loading) {
            loading = false;
            load().then((_) {
              if (context.mounted) setStateDialog(() {});
            });
          }
          return AlertDialog(
            backgroundColor: AppTheme.surface,
            title: const Text('Discover Groups', style: TextStyle(color: Colors.white)),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: queryController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Search groups',
                      hintStyle: TextStyle(color: Colors.white54),
                    ),
                    onSubmitted: (v) async {
                      await load(query: v.trim());
                      if (context.mounted) setStateDialog(() {});
                    },
                  ),
                  const SizedBox(height: 10),
                  if (groups.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'No groups found',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: groups.length,
                        itemBuilder: (context, index) {
                          final group = groups[index];
                          final relation = (group['relation'] ?? 'none').toString();
                          final id = (group['id'] as num?)?.toInt();
                          return ListTile(
                            title: Text(
                              (group['name'] ?? '').toString(),
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              '${group['member_count'] ?? 0} members',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
                            ),
                            trailing: relation == 'member' || relation == 'admin'
                                ? const Text('Joined', style: TextStyle(color: Colors.greenAccent))
                                : relation == 'pending'
                                    ? const Text('Pending', style: TextStyle(color: Colors.orangeAccent))
                                    : TextButton(
                                        onPressed: id == null
                                            ? null
                                            : () async {
                                                try {
                                                  await chatProvider.requestJoinGroup(authProvider.apiClient, id);
                                                  await load(query: queryController.text.trim());
                                                  if (context.mounted) setStateDialog(() {});
                                                } catch (e) {
                                                  if (!context.mounted) return;
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
                                                  );
                                                }
                                              },
                                        child: const Text('Join'),
                                      ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            ],
          );
        },
      ),
    );
    if (!mounted) return;
    await _loadChats();
  }

  Future<void> _showJoinRequestsDialog() async {
    final authProvider = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();
    List<Map<String, dynamic>> requests = [];
    bool loading = true;

    Future<void> load() async {
      requests = await chatProvider.fetchManagedGroupJoinRequests(authProvider.apiClient);
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          if (loading) {
            loading = false;
            load().then((_) {
              if (context.mounted) setStateDialog(() {});
            });
          }
          final screenSize = MediaQuery.of(context).size;
          final dialogWidth = screenSize.width < 520 ? screenSize.width - 24 : 460.0;
          final dialogMaxHeight = screenSize.height * 0.68;
          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
            backgroundColor: AppTheme.surface,
            title: const Text('Group Join Requests', style: TextStyle(color: Colors.white)),
            content: SizedBox(
              width: dialogWidth,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: dialogMaxHeight),
                child: requests.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'No pending requests',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: requests.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final request = requests[index];
                          final requestId = (request['id'] as num?)?.toInt();
                          final player =
                              (request['player'] as Map?)?['username']?.toString() ??
                                  'Player';
                          final roomName = ((request['room'] as Map?)?['name'] ?? '')
                              .toString();
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  player,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Wants to join $roomName',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.72),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: requestId == null
                                            ? null
                                            : () async {
                                                await chatProvider.reviewGroupJoinRequest(
                                                  authProvider.apiClient,
                                                  requestId: requestId,
                                                  action: 'approve',
                                                );
                                                await load();
                                                if (context.mounted) {
                                                  setStateDialog(() {});
                                                }
                                              },
                                        child: const Text('Approve'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextButton(
                                        onPressed: requestId == null
                                            ? null
                                            : () async {
                                                await chatProvider.reviewGroupJoinRequest(
                                                  authProvider.apiClient,
                                                  requestId: requestId,
                                                  action: 'reject',
                                                );
                                                await load();
                                                if (context.mounted) {
                                                  setStateDialog(() {});
                                                }
                                              },
                                        child: const Text('Reject'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            ],
          );
        },
      ),
    );
    if (!mounted) return;
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

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    int badgeCount = 0,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 16),
          label: Text(label),
        ),
        if (badgeCount > 0)
          Positioned(
            right: -6,
            top: -8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                badgeCount > 99 ? '99+' : '$badgeCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
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
              final isAgentUser = auth.user?.isAgent ?? false;
              final isPlayerUser = auth.user?.isPlayer ?? false;
              final currentUserId = auth.user?.id;
              final rooms = chatProvider.activeChats;
              Room? supportRoom;
              for (final room in rooms) {
                if (room.roomType == 'support') {
                  supportRoom = room;
                  break;
                }
              }
              final directRoomsRaw =
                  rooms.where((r) => r.roomType == 'direct_agent').toList();
              final groupRoomsRaw = rooms.where((r) => r.roomType == 'group').toList();
              final otherRooms = _buildPrioritizedRooms(
                directRoomsRaw,
                userType: userType,
                currentUserId: currentUserId,
              );
              groupRoomsRaw.sort((a, b) {
                final unreadCompare = b.unreadCount.compareTo(a.unreadCount);
                if (unreadCompare != 0) return unreadCompare;
                return _compareNullableDateDesc(a.lastActivity, b.lastActivity);
              });

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
                  if (isPlayerUser || isAgentUser) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (isPlayerUser)
                          _actionButton(
                            icon: Icons.person_search,
                            label: 'Find Agents',
                            onPressed: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const AgentSearchScreen(),
                                ),
                              );
                              if (!mounted) return;
                              await _loadChats();
                            },
                          ),
                        if (isPlayerUser)
                          _actionButton(
                            icon: Icons.groups_2,
                            label: 'Discover Groups',
                            onPressed: _showGroupDiscoveryDialog,
                          ),
                        if (isAgentUser) ...[
                          _actionButton(
                            icon: Icons.group_add,
                            label: 'Create Group',
                            onPressed: _showCreateGroupDialog,
                          ),
                          _actionButton(
                            icon: Icons.how_to_reg,
                            label: 'Join Requests',
                            onPressed: _showJoinRequestsDialog,
                            badgeCount: _pendingGroupRequests,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isAgentUser ? 'Direct Chats' : 'Chats',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (isAgentUser)
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
                  if (isAgentUser) ...[
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
                  const SizedBox(height: 14),
                  Text(
                    'Groups',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (groupRoomsRaw.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surface.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Text(
                        'No groups available.',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
                      ),
                    )
                  else
                    ...groupRoomsRaw.map(
                      (room) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.surface.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: AppTheme.accent,
                            child: Icon(Icons.group, color: Colors.black),
                          ),
                          title: Text(
                            _titleForRoom(room),
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            room.userIsGroupAdmin
                                ? '${room.groupMemberCount} members • You are admin'
                                : '${room.groupMemberCount} members',
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
