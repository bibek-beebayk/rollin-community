import 'user.dart';

class SocialConnection {
  final int id;
  final User requester;
  final User receiver;
  final String connectionType;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  SocialConnection({
    required this.id,
    required this.requester,
    required this.receiver,
    required this.connectionType,
    required this.status,
    this.createdAt,
    this.updatedAt,
  });

  factory SocialConnection.fromJson(Map<String, dynamic> json) {
    return SocialConnection(
      id: (json['id'] as num?)?.toInt() ?? 0,
      requester: User.fromJson(
        (json['requester'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      receiver: User.fromJson(
        (json['receiver'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      connectionType: (json['connection_type'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }
}

