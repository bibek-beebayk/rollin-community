import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../models/room.dart';
import '../api/api_client.dart';

class ChatProvider with ChangeNotifier {
  // Notification Channel
  WebSocketChannel? _notificationChannel;
  StreamSubscription? _notificationSubscription;

  // Room mapping caches
  final Map<int, List<Message>> _roomMessagesCache = {};
  final Map<int, WebSocketChannel> _channels = {};
  final Map<int, StreamSubscription> _subscriptions = {};
  final Map<int, String> _roomAccessTokens = {};
  final Map<int, Timer> _roomReconnectTimers = {};
  final Set<int> _manualRoomDisconnects = {};

  bool _isConnected = false;
  int? _currentRoomId;
  bool _isChatTabActive = false;
  bool _isRouteChatOpen = false;
  bool _unreadLoaded = false;
  final Map<int, int> _persistedUnread = {};

  String? _notificationAccessToken;
  Timer? _notificationReconnectTimer;
  bool _manualNotificationDisconnect = false;

  // ... (getters)
  List<Message> get messages => _roomMessagesCache[_currentRoomId] ?? [];
  bool get isConnected => _isConnected;
  int? get currentRoomId => _currentRoomId;
  bool get isChatTabActive => _isChatTabActive;
  bool get isRouteChatOpen => _isRouteChatOpen;

  void setChatTabActive(bool isActive) {
    _isChatTabActive = isActive;
  }

  void setRouteChatOpen(bool isOpen) {
    _isRouteChatOpen = isOpen;
  }

  void handleAppResumed(String accessToken) {
    _notificationAccessToken = accessToken;

    // Ensure notification socket is alive.
    if (_notificationChannel == null) {
      connectNotifications(accessToken);
    }

    // Ensure currently viewed room socket is alive.
    final roomId = _currentRoomId;
    if (roomId != null && !_channels.containsKey(roomId)) {
      connect(roomId, accessToken);
    }
  }

  bool hasCachedRoom(int roomId) {
    return _roomMessagesCache.containsKey(roomId) &&
        _roomMessagesCache[roomId]!.isNotEmpty;
  }

  List<Room> _activeChats = [];
  List<Room> get activeChats => _activeChats;

  // ... (active chats logic remains)

  // ... participants getter
  List<User> get participants {
    final Map<int, User> uniqueUsers = {};
    final currentMsgs = _roomMessagesCache[_currentRoomId] ?? [];
    for (var msg in currentMsgs) {
      if (!uniqueUsers.containsKey(msg.sender.id)) {
        uniqueUsers[msg.sender.id] = msg.sender;
      }
    }
    return uniqueUsers.values.toList();
  }

  List<Room> _supportStations = []; // Available stations/queues
  List<Room> get supportStations => _supportStations;

  Future<void> _ensureUnreadLoaded() async {
    if (_unreadLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('chat_unread_counts');
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _persistedUnread.clear();
          decoded.forEach((k, v) {
            final roomId = int.tryParse(k);
            final count = v is int ? v : int.tryParse('$v');
            if (roomId != null && count != null && count > 0) {
              _persistedUnread[roomId] = count;
            }
          });
        }
      } catch (_) {
        // ignore malformed local cache
      }
    }
    _unreadLoaded = true;
  }

  Future<void> _saveUnreadCounts() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, int>{};
    for (final room in _activeChats) {
      if (room.unreadCount > 0) {
        payload['${room.id}'] = room.unreadCount;
      }
    }
    await prefs.setString('chat_unread_counts', jsonEncode(payload));
  }

  Future<void> fetchActiveChats(ApiClient apiClient) async {
    try {
      await _ensureUnreadLoaded();
      final response = await apiClient.get('/api/rooms/');
      final List<dynamic> data =
          (response is Map && response.containsKey('data'))
              ? response['data']
              : response;

      debugPrint('DEBUG: Active Chats raw data: $data');

      // Filter for active chats if needed, or assume backend returns relevant ones
      // For now, we take all returned rooms as "Active Chats" for the staff
      _activeChats = data.map((j) => Room.fromJson(j)).toList();

      // Merge server unread with locally persisted unread to survive app restarts.
      for (final room in _activeChats) {
        // If user is actively viewing this room, force unread to 0 locally.
        final isActivelyViewingChat = _isChatTabActive || _isRouteChatOpen;
        if (isActivelyViewingChat && _currentRoomId == room.id) {
          room.unreadCount = 0;
          _persistedUnread.remove(room.id);
          continue;
        }

        final localUnread = _persistedUnread[room.id] ?? 0;
        if (localUnread > room.unreadCount) {
          room.unreadCount = localUnread;
        }
      }

      await _saveUnreadCounts();
      notifyListeners();
    } catch (e) {
      debugPrint('ChatProvider: Error fetching active chats: $e');
      rethrow;
    }
  }

  Future<void> fetchSupportStations(ApiClient apiClient) async {
    try {
      final response = await apiClient.get('/api/support-rooms/');
      final List<dynamic> data =
          (response is Map && response.containsKey('data'))
              ? response['data']
              : response;

      _supportStations = data.map((j) => Room.fromJson(j)).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('ChatProvider: Error fetching support stations: $e');
      // Don't rethrow necessarily, just log
    }
  }

  Future<void> joinStation(ApiClient apiClient, int roomId) async {
    try {
      await apiClient.post('/api/support-rooms/$roomId/enter/');
      await fetchSupportStations(apiClient); // Refresh station status
      await fetchActiveChats(apiClient); // Refresh active chats
    } catch (e) {
      debugPrint('ChatProvider: Error joining station: $e');
      rethrow;
    }
  }

  Future<void> leaveStation(ApiClient apiClient, int roomId) async {
    try {
      await apiClient.post('/api/support-rooms/$roomId/leave/');
      await fetchSupportStations(apiClient); // Refresh station status
      await fetchActiveChats(apiClient); // Refresh active chats
    } catch (e) {
      debugPrint('ChatProvider: Error leaving station: $e');
      rethrow;
    }
  }

  Future<Room?> joinSupportRoom(ApiClient apiClient) async {
    try {
      final response = await apiClient.get('/api/rooms/');

      List<dynamic> data = [];
      if (response is Map && response.containsKey('data')) {
        data = response['data'];
      } else if (response is List) {
        data = response;
      }
      if (response is Map && response.containsKey('results')) {
        data = response['results'];
      }

      if (data.isNotEmpty) {
        return Room.fromJson(data[0]);
      }
      return null;
    } catch (e) {
      debugPrint('ChatProvider: Error joining support room: $e');
      rethrow;
    }
  }

  Future<void> fetchMessages(int roomId) async {
    try {
      final response =
          await ApiClient().get('/api/rooms/$roomId/messages/?limit=50');
      // API might return list directly or {data: []}
      final List<dynamic> data =
          (response is Map && response.containsKey('results'))
              ? response['results']
              : (response is Map && response.containsKey('data'))
                  ? response['data']
                  : (response is List ? response : []);

      final history = <Message>[];
      for (var item in data) {
        try {
          history.add(Message.fromJson(item));
        } catch (e) {
          // Skip invalid messages
        }
      }
      debugPrint(
          'DEBUG: Parsed ${history.length} valid messages from ${data.length} items');
      setHistory(roomId, history);
    } catch (e) {
      debugPrint('ChatProvider: Error fetching history: $e');
    }
  }

  void setHistory(int roomId, List<Message> history) {
    _roomMessagesCache.putIfAbsent(roomId, () => []);

    // Add only messages we don't already have to prevent ListView rebuilding and flashing
    bool updated = false;
    for (var msg in history) {
      if (!_roomMessagesCache[roomId]!.any((m) => m.id == msg.id)) {
        _roomMessagesCache[roomId]!.add(msg);
        updated = true;
      }
    }

    if (updated) {
      _roomMessagesCache[roomId]!
          .sort((a, b) => a.timestamp.compareTo(b.timestamp));
      notifyListeners();
    }
  }

  void connect(int roomId, String accessToken) {
    _currentRoomId = roomId;
    _roomAccessTokens[roomId] = accessToken;
    _manualRoomDisconnects.remove(roomId);
    _roomReconnectTimers[roomId]?.cancel();
    _roomReconnectTimers.remove(roomId);

    if (_channels.containsKey(roomId)) {
      _isConnected = true;
      notifyListeners();
      return;
    }

    // WS URL formatting
    final baseUrl = ApiClient.baseUrl;
    final scheme = baseUrl.startsWith('https') ? 'wss' : 'ws';
    final host = baseUrl
        .replaceFirst(RegExp(r'https?://'), '')
        .replaceAll(RegExp(r'/$'), '');

    final url = '$scheme://$host/ws/chat/$roomId/?token=${accessToken.trim()}';

    try {
      debugPrint('Connecting to WS: $url');
      debugPrint('WS Origin: ${ApiClient.baseUrl}');

      _channels[roomId] = IOWebSocketChannel.connect(
        url,
        headers: {
          'Origin': ApiClient.baseUrl,
        },
      );
      _isConnected = true;
      notifyListeners();

      // Store subscription to cancel it later
      _subscriptions[roomId] = _channels[roomId]!.stream.listen(
        (data) {
          _handleMessage(roomId, data);
        },
        onDone: () {
          debugPrint('WS Disconnected (Room: $roomId)');
          _channels.remove(roomId);
          _subscriptions.remove(roomId);
          // Only update state if this is still the current room's connection
          if (_currentRoomId == roomId) {
            _isConnected = false;
            notifyListeners();
          }
          _scheduleRoomReconnect(roomId);
        },
        onError: (error) {
          debugPrint('WS Error (Room: $roomId): $error');
          _channels.remove(roomId);
          _subscriptions.remove(roomId);
          if (_currentRoomId == roomId) {
            _isConnected = false;
            notifyListeners();
          }
          _scheduleRoomReconnect(roomId);
        },
      );
    } catch (e) {
      debugPrint('WS Connection Exception: $e');
      if (_currentRoomId == roomId) {
        _isConnected = false;
      }
      notifyListeners();
    }
  }

  void connectNotifications(String accessToken) {
    _notificationAccessToken = accessToken;
    _manualNotificationDisconnect = false;
    _notificationReconnectTimer?.cancel();
    _notificationReconnectTimer = null;

    if (_notificationChannel != null) {
      debugPrint('DEBUG: Notification channel already connected.');
      return;
    }

    final baseUrl = ApiClient.baseUrl;
    final scheme = baseUrl.startsWith('https') ? 'wss' : 'ws';
    final host = baseUrl
        .replaceFirst(RegExp(r'https?://'), '')
        .replaceAll(RegExp(r'/$'), '');

    final url = '$scheme://$host/ws/notifications/?token=${accessToken.trim()}';

    try {
      debugPrint('DEBUG: Connecting to Notification WS: $url');
      _notificationChannel = IOWebSocketChannel.connect(
        url,
        headers: {'Origin': ApiClient.baseUrl},
      );

      _notificationSubscription = _notificationChannel!.stream.listen(
        (data) {
          debugPrint('DEBUG: Notification WS Received: $data');
          _handleNotification(data);
        },
        onDone: () {
          debugPrint('DEBUG: Notification WS Disconnected (Done)');
          _notificationChannel = null;
          _scheduleNotificationReconnect();
        },
        onError: (error) {
          debugPrint('DEBUG: Notification WS Error: $error');
          _notificationChannel = null;
          _scheduleNotificationReconnect();
        },
      );
    } catch (e) {
      debugPrint('DEBUG: Notification WS Connection Exception: $e');
    }
  }

  void _handleNotification(dynamic data) {
    try {
      final json = jsonDecode(data);
      debugPrint('DEBUG: Handling Notification: $json');
      if (json['type'] == 'new_message_notification') {
        final dynamic roomIdRaw = json['room_id'];
        final int? roomId = roomIdRaw is int
            ? roomIdRaw
            : int.tryParse(roomIdRaw?.toString() ?? '');
        if (roomId == null) {
          debugPrint('DEBUG: Invalid room_id in notification: $roomIdRaw');
          return;
        }
        debugPrint(
            'DEBUG: New Message for Room $roomId. Current Room: $_currentRoomId, ChatTabActive: $_isChatTabActive, RouteChatOpen: $_isRouteChatOpen');

        // Count unread unless user is actively viewing this exact room.
        final isActivelyViewingChat = _isChatTabActive || _isRouteChatOpen;
        final isViewingSameRoom =
            isActivelyViewingChat && _currentRoomId == roomId;
        if (!isViewingSameRoom) {
          // Find the room in active chats and increment unread
          final roomIndex = _activeChats.indexWhere((r) => r.id == roomId);
          debugPrint('DEBUG: Found room in active chats? Index: $roomIndex');

          if (roomIndex != -1) {
            _activeChats[roomIndex].unreadCount++;
            _persistedUnread[roomId] = _activeChats[roomIndex].unreadCount;
            unawaited(_saveUnreadCounts());
            debugPrint(
                'DEBUG: Incremented unread count to ${_activeChats[roomIndex].unreadCount}');
            notifyListeners();
          } else {
            debugPrint(
                'DEBUG: Room $roomId not found in activeChats list. Refreshing active chats.');
            // New/previously-unlisted room: refresh from server so dashboard badges
            // update without requiring manual screen refresh.
            unawaited(fetchActiveChats(ApiClient()));
          }
        } else {
          debugPrint(
              'DEBUG: Ignored notification because user is actively viewing this room.');
        }
      }
    } catch (e) {
      debugPrint('DEBUG: Error parsing notification: $e');
    }
  }

  // ... (existing methods)
  // ... _handleMessage, sendMessage, setHistory ...
  void _handleMessage(int roomId, dynamic data) {
    try {
      final json = jsonDecode(data);
      debugPrint('WS Message (Room: $roomId): $json');

      if (json['type'] == 'websocket.accept') {
        debugPrint('WS Debug: Connection accepted (Room: $roomId)');
        return;
      }

      if (json['type'] == 'chat_message') {
        try {
          final msg = Message.fromJson(json);
          // Ensure room exists in cache
          _roomMessagesCache.putIfAbsent(roomId, () => []);

          // Deduplicate
          if (!_roomMessagesCache[roomId]!.any((m) => m.id == msg.id)) {
            _roomMessagesCache[roomId]!.add(msg);
            _roomMessagesCache[roomId]!
                .sort((a, b) => a.timestamp.compareTo(b.timestamp));
            if (_currentRoomId == roomId) {
              // This chat is currently open; unread should never accumulate here.
              clearUnread(roomId);
            } else {
              notifyListeners();
            }
          }
        } catch (e) {
          debugPrint('WS Debug: Error parsing message: $e');
        }
      }
    } catch (e) {
      debugPrint('Error parsing message: $e');
    }
  }

  // Method to clear unreads when entering a chat
  void clearUnread(int roomId) {
    try {
      final roomIndex = _activeChats.indexWhere((r) => r.id == roomId);
      if (roomIndex != -1) {
        // Since Room fields are final, we might need a way to update it.
        // Option 1: Mutable unreadCount (removed final) -> Done in Room model
        _activeChats[roomIndex].unreadCount = 0;
        _persistedUnread.remove(roomId);
        unawaited(_saveUnreadCounts());
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error clearing unread: $e');
    }
  }

  // Clear all unread counters locally (useful when user is actively in Chat tab).
  void clearAllUnread() {
    bool updated = false;
    for (final room in _activeChats) {
      if (room.unreadCount > 0) {
        room.unreadCount = 0;
        _persistedUnread.remove(room.id);
        updated = true;
      }
    }
    if (updated) {
      unawaited(_saveUnreadCounts());
      notifyListeners();
    }
  }

  Future<void> uploadFile(String filePath, int roomId) async {
    // We don't send via WebSocket for upload, we hit the API
    // The API will trigger a WS message to all users
    try {
      await ApiClient().postMultipart(
        '/api/rooms/$roomId/attachments/',
        filePath,
      );
    } catch (e) {
      debugPrint('ChatProvider: Error uploading file: $e');
      rethrow;
    }
  }

  void sendMessage(int roomId, String content) {
    if (_channels.containsKey(roomId) && _isConnected) {
      _channels[roomId]!.sink.add(
            jsonEncode({'type': 'chat_message', 'message': content}),
          );
    } else {
      debugPrint(
          'ChatProvider: Cannot send message, not connected to Room $roomId.');
    }
  }

  void disconnect() {
    _manualRoomDisconnects.addAll(_channels.keys);

    for (var timer in _roomReconnectTimers.values) {
      timer.cancel();
    }
    _roomReconnectTimers.clear();

    for (var sub in _subscriptions.values) {
      sub.cancel(); // Cancel listener first!
    }
    _subscriptions.clear();

    for (var channel in _channels.values) {
      channel.sink.close();
    }
    _channels.clear();

    // Also disconnect notifications on full disconnect (logout)
    // Or we might want to keep it? usually disconnect() is called on room leave.
    // Wait, disconnect() here is generic. If it's used for switching rooms, we SHOULD NOT close notifications.
    // Checking usage: disconnect() is called in connect() (switching rooms) and dispose().
    // So we should NOT close notifications here unless we split 'disconnectChat' and 'dispose'.
    // Let's create a separate disconnectNotifications logic and call it in dispose.

    _isConnected = false;
    _currentRoomId = null;
    notifyListeners();
  }

  void disconnectRoom(int roomId) {
    _manualRoomDisconnects.add(roomId);
    _roomReconnectTimers[roomId]?.cancel();
    _roomReconnectTimers.remove(roomId);

    _subscriptions[roomId]?.cancel();
    _subscriptions.remove(roomId);

    _channels[roomId]?.sink.close();
    _channels.remove(roomId);

    if (_currentRoomId == roomId) {
      _currentRoomId = null;
      _isConnected = false;
      notifyListeners();
    }
  }

  void disconnectNotifications() {
    _manualNotificationDisconnect = true;
    _notificationReconnectTimer?.cancel();
    _notificationReconnectTimer = null;
    _notificationSubscription?.cancel();
    _notificationSubscription = null;
    if (_notificationChannel != null) {
      _notificationChannel!.sink.close();
      _notificationChannel = null;
    }
  }

  void _scheduleRoomReconnect(int roomId) {
    if (_manualRoomDisconnects.contains(roomId)) return;
    if (_currentRoomId != roomId) return;

    final token = _roomAccessTokens[roomId];
    if (token == null || token.isEmpty) return;

    _roomReconnectTimers[roomId]?.cancel();
    _roomReconnectTimers[roomId] = Timer(const Duration(seconds: 2), () {
      if (_manualRoomDisconnects.contains(roomId)) return;
      if (_currentRoomId != roomId) return;
      if (_channels.containsKey(roomId)) return;
      connect(roomId, token);
    });
  }

  void _scheduleNotificationReconnect() {
    if (_manualNotificationDisconnect) return;
    final token = _notificationAccessToken;
    if (token == null || token.isEmpty) return;

    _notificationReconnectTimer?.cancel();
    _notificationReconnectTimer = Timer(const Duration(seconds: 2), () {
      if (_manualNotificationDisconnect) return;
      if (_notificationChannel != null) return;
      connectNotifications(token);
    });
  }

  @override
  void dispose() {
    disconnect();
    disconnectNotifications();
    super.dispose();
  }
}
