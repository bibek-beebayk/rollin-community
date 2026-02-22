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
    this.attachment,
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
              userType: json['user_type'] ??
                  'player', // Use user_type from JSON if available
              isVerified: false,
              verificationStatus: 'none',
            ),
      content: json['content'] ?? (json['message'] ?? ''),
      timestamp: _parseDate(json['timestamp']) ?? DateTime.now(),
      isRead: json['is_read'] ?? false,
      isEdited: json['is_edited'] ?? false,
      type: json['type'],
      attachment: json['attachment'] != null
          ? (json['attachment'] is String
              ? MessageAttachment(
                  file: json['attachment'],
                  fileType: _inferMimeType(json['attachment']),
                  filename: json['attachment'].split('/').last,
                )
              : MessageAttachment.fromJson(json['attachment']))
          : null,
    );
  }

  static String _inferMimeType(String path) {
    final lower = path.toLowerCase();
    final cleanPath = lower.split('?').first;
    if (cleanPath.endsWith('.jpg') ||
        cleanPath.endsWith('.jpeg') ||
        cleanPath.endsWith('.png') ||
        cleanPath.endsWith('.gif') ||
        cleanPath.endsWith('.webp')) {
      return 'image/jpeg';
    }
    if (cleanPath.endsWith('.mp4') || cleanPath.endsWith('.mov')) {
      return 'video/mp4';
    }
    if (cleanPath.endsWith('.pdf')) {
      return 'application/pdf';
    }
    return 'application/octet-stream';
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

  final MessageAttachment? attachment;
}

class MessageAttachment {
  final String file;
  final String? filename;
  final String? fileType;

  MessageAttachment({
    required this.file,
    this.filename,
    this.fileType,
  });

  factory MessageAttachment.fromJson(Map<String, dynamic> json) {
    String fileUrl = json['file'] ?? '';
    return MessageAttachment(
      file: fileUrl,
      filename: json['filename'],
      fileType: json['file_type'] ?? _inferMimeType(fileUrl),
    );
  }

  static String _inferMimeType(String path) {
    final lower = path.toLowerCase();
    // Strip query parameters for extension checking
    final cleanPath = lower.split('?').first;

    if (cleanPath.endsWith('.jpg') ||
        cleanPath.endsWith('.jpeg') ||
        cleanPath.endsWith('.png') ||
        cleanPath.endsWith('.gif') ||
        cleanPath.endsWith('.webp')) {
      return 'image/jpeg';
    }
    if (cleanPath.endsWith('.mp4') || cleanPath.endsWith('.mov')) {
      return 'video/mp4';
    }
    if (cleanPath.endsWith('.pdf')) {
      return 'application/pdf';
    }
    return 'application/octet-stream';
  }
}
