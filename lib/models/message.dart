import 'user.dart';

class Message {
  final int id;
  final int roomId;
  final User sender;
  final String content;
  final DateTime timestamp;
  final bool isRead;
  final bool isEdited;
  final String? type;

  Message({
    required this.id,
    required this.roomId,
    required this.sender,
    required this.content,
    required this.timestamp,
    this.isRead = false,
    this.isEdited = false,
    this.type,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: _parseInt(json['id']) ?? _parseInt(json['message_id']) ?? 0,
      roomId: _parseInt(json['room']) ?? 0,
      sender: (json['sender'] != null && json['sender'] is Map<String, dynamic>)
          ? User.fromJson(json['sender'])
          : User(
              id: _parseInt(json['user_id']) ??
                  (_parseInt(json['sender']) ?? 0),
              username: json['username'] ?? 'Unknown',
              email: '',
              userType: 'player', // Default to player if unknown
              isVerified: false,
            ),
      content: json['content'] ?? (json['message'] ?? ''),
      timestamp: _parseDate(json['timestamp']) ?? DateTime.now(),
      isRead: json['is_read'] ?? false,
      isEdited: json['is_edited'] ?? false,
      type: json['type'],
    );
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
