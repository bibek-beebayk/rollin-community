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

  Future<void> fetchActiveChats(ApiClient apiClient) async {
    // ... (same as before)
    try {
      final response = await apiClient.get('/api/rooms/');
      final List<dynamic> data =
          (response is Map && response.containsKey('data'))
              ? response['data']
              : response;

      print('DEBUG: Active Chats raw data: $data'); // Debug print

      _activeChats = data.map((j) => Room.fromJson(j)).toList();
      notifyListeners();
    } catch (e) {
      print('ChatProvider: Error fetching active chats: $e');
      rethrow;
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
    _isConnected = false;
    _currentRoomId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
