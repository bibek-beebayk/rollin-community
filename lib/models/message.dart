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
    final dynamic senderRaw = json['sender'];
    final bool hasSenderMap = senderRaw is Map<String, dynamic>;

    int? parsedSenderId;
    String parsedSenderUsername = 'Unknown';
    String parsedSenderType = 'client';

    if (hasSenderMap) {
      final senderMap = senderRaw;
      parsedSenderId = _parseInt(senderMap['id']);
      parsedSenderUsername = (senderMap['username'] ?? 'Unknown').toString();
      parsedSenderType = (senderMap['user_type'] ?? 'client').toString();
    } else {
      parsedSenderId =
          _parseInt(json['user_id']) ?? _parseInt(json['sender']) ?? 0;
      parsedSenderUsername = (json['username'] ??
              json['sender_username'] ??
              json['sender_name'] ??
              'Unknown')
          .toString();
      parsedSenderType =
          (json['user_type'] ?? json['sender_type'] ?? 'client').toString();
    }

    return Message(
      id: _parseInt(json['id']) ?? _parseInt(json['message_id']) ?? 0,
      roomId: _parseInt(json['room']) ?? _parseInt(json['room_id']) ?? 0,
      sender: hasSenderMap
          ? User.fromJson(senderRaw)
          : User(
              id: parsedSenderId ?? 0,
              username: parsedSenderUsername,
              email: '',
              userType: parsedSenderType,
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
