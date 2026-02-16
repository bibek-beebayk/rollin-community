import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../models/room.dart';
import '../api/api_client.dart';

class ChatProvider with ChangeNotifier {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription; // Add this

  // Notification Channel
  WebSocketChannel? _notificationChannel;
  StreamSubscription? _notificationSubscription;

  final List<Message> _messages = [];
  bool _isConnected = false;
  int? _currentRoomId;

  // ... (getters)
  List<Message> get messages => _messages;
  bool get isConnected => _isConnected;
  List<Room> _activeChats = [];
  List<Room> get activeChats => _activeChats;

  // ... (active chats logic remains)

  // ... participants getter
  List<User> get participants {
    final Map<int, User> uniqueUsers = {};
    for (var msg in _messages) {
      if (!uniqueUsers.containsKey(msg.sender.id)) {
        uniqueUsers[msg.sender.id] = msg.sender;
      }
    }
    return uniqueUsers.values.toList();
  }

  List<Room> _supportStations = []; // Available stations/queues
  List<Room> get supportStations => _supportStations;

  Future<void> fetchActiveChats(ApiClient apiClient) async {
    try {
      final response = await apiClient.get('/api/rooms/');
      final List<dynamic> data =
          (response is Map && response.containsKey('data'))
              ? response['data']
              : response;

      print('DEBUG: Active Chats raw data: $data');

      // Filter for active chats if needed, or assume backend returns relevant ones
      // For now, we take all returned rooms as "Active Chats" for the staff
      _activeChats = data.map((j) => Room.fromJson(j)).toList();
      notifyListeners();
    } catch (e) {
      print('ChatProvider: Error fetching active chats: $e');
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
      print('ChatProvider: Error fetching support stations: $e');
      // Don't rethrow necessarily, just log
    }
  }

  Future<void> joinStation(ApiClient apiClient, int roomId) async {
    try {
      await apiClient.post('/api/support-rooms/$roomId/enter/');
      await fetchSupportStations(apiClient); // Refresh station status
      await fetchActiveChats(apiClient); // Refresh active chats
    } catch (e) {
      print('ChatProvider: Error joining station: $e');
      rethrow;
    }
  }

  Future<void> leaveStation(ApiClient apiClient, int roomId) async {
    try {
      await apiClient.post('/api/support-rooms/$roomId/leave/');
      await fetchSupportStations(apiClient); // Refresh station status
    } catch (e) {
      print('ChatProvider: Error leaving station: $e');
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
      print(
          'DEBUG: Parsed ${history.length} valid messages from ${data.length} items');
      setHistory(history);
    } catch (e) {
      print('ChatProvider: Error fetching history: $e');
    }
  }

  void connect(int roomId, String accessToken) {
    if (_currentRoomId == roomId && _isConnected) return;

    disconnect();
    _currentRoomId = roomId;
    _messages.clear();

    // WS URL formatting
    final baseUrl = ApiClient.baseUrl;
    final scheme = baseUrl.startsWith('https') ? 'wss' : 'ws';
    final host = baseUrl
        .replaceFirst(RegExp(r'https?://'), '')
        .replaceAll(RegExp(r'/$'), '');

    final url = '$scheme://$host/ws/chat/$roomId/?token=${accessToken.trim()}';

    try {
      print('Connecting to WS: $url');
      print('WS Origin: ${ApiClient.baseUrl}');

      _channel = IOWebSocketChannel.connect(
        url,
        headers: {
          'Origin': ApiClient.baseUrl,
        },
      );
      _isConnected = true;
      notifyListeners();

      // Store subscription to cancel it later
      _subscription = _channel!.stream.listen(
        (data) {
          _handleMessage(data);
        },
        onDone: () {
          print('WS Disconnected (Room: $roomId)');
          // Only update state if this is still the current room's connection
          if (_currentRoomId == roomId) {
            _isConnected = false;
            notifyListeners();
          }
        },
        onError: (error) {
          print('WS Error (Room: $roomId): $error');
          if (_currentRoomId == roomId) {
            _isConnected = false;
            notifyListeners();
          }
        },
      );
    } catch (e) {
      print('WS Connection Exception: $e');
      _isConnected = false;
      notifyListeners();
    }
  }

  void connectNotifications(String accessToken) {
    if (_notificationChannel != null) {
      print('DEBUG: Notification channel already connected.');
      return;
    }

    final baseUrl = ApiClient.baseUrl;
    final scheme = baseUrl.startsWith('https') ? 'wss' : 'ws';
    final host = baseUrl
        .replaceFirst(RegExp(r'https?://'), '')
        .replaceAll(RegExp(r'/$'), '');

    final url = '$scheme://$host/ws/notifications/?token=${accessToken.trim()}';

    try {
      print('DEBUG: Connecting to Notification WS: $url');
      _notificationChannel = IOWebSocketChannel.connect(
        url,
        headers: {'Origin': ApiClient.baseUrl},
      );

      _notificationSubscription = _notificationChannel!.stream.listen(
        (data) {
          print('DEBUG: Notification WS Received: $data');
          _handleNotification(data);
        },
        onDone: () {
          print('DEBUG: Notification WS Disconnected (Done)');
          _notificationChannel = null;
          // Reconnect logic could go here
        },
        onError: (error) {
          print('DEBUG: Notification WS Error: $error');
          _notificationChannel = null;
        },
      );
    } catch (e) {
      print('DEBUG: Notification WS Connection Exception: $e');
    }
  }

  void _handleNotification(dynamic data) {
    try {
      final json = jsonDecode(data);
      print('DEBUG: Handling Notification: $json');
      if (json['type'] == 'new_message_notification') {
        final roomId = json['room_id'];
        print(
            'DEBUG: New Message for Room $roomId. Current Room: $_currentRoomId');

        // If message is for a room we are NOT currently viewing
        if (_currentRoomId != roomId) {
          // Find the room in active chats and increment unread
          final roomIndex = _activeChats.indexWhere((r) => r.id == roomId);
          print('DEBUG: Found room in active chats? Index: $roomIndex');

          if (roomIndex != -1) {
            _activeChats[roomIndex].unreadCount++;
            print(
                'DEBUG: Incremented unread count to ${_activeChats[roomIndex].unreadCount}');
            notifyListeners();
          } else {
            print('DEBUG: Room $roomId not found in activeChats list.');
          }
        } else {
          print('DEBUG: Ignored notification because we are in the room.');
        }
      }
    } catch (e) {
      print('DEBUG: Error parsing notification: $e');
    }
  }

  // ... (existing methods)
  // ... _handleMessage, sendMessage, setHistory ...
  void _handleMessage(dynamic data) {
    try {
      final json = jsonDecode(data);
      print('WS Message: $json');

      if (json['type'] == 'websocket.accept') {
        print('WS Debug: Connection accepted');
        return;
      }

      if (json['type'] == 'chat_message') {
        try {
          final msg = Message.fromJson(json);
          // Deduplicate
          if (!_messages.any((m) => m.id == msg.id)) {
            _messages.add(msg);
            _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
            notifyListeners();
          }
        } catch (e) {
          print('WS Debug: Error parsing message: $e');
        }
      }
    } catch (e) {
      print('Error parsing message: $e');
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
        notifyListeners();
      }
    } catch (e) {
      print('Error clearing unread: $e');
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
      print('ChatProvider: Error uploading file: $e');
      rethrow;
    }
  }

  void sendMessage(String content) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(
        jsonEncode({'type': 'chat_message', 'message': content}),
      );
    } else {
      print('ChatProvider: Cannot send message, not connected.');
    }
  }

  void setHistory(List<Message> history) {
    _messages.clear();
    _messages.addAll(history);
    _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    notifyListeners();
  }

  void disconnect() {
    _subscription?.cancel(); // Cancel listener first!
    _subscription = null;

    if (_channel != null) {
      _channel!.sink.close();
      _channel = null;
    }

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

  void disconnectNotifications() {
    _notificationSubscription?.cancel();
    _notificationSubscription = null;
    if (_notificationChannel != null) {
      _notificationChannel!.sink.close();
      _notificationChannel = null;
    }
  }

  @override
  void dispose() {
    disconnect();
    disconnectNotifications();
    super.dispose();
  }
}
