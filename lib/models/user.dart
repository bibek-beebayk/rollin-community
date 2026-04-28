import 'package:flutter/foundation.dart';
class User {
  final int id;
  final String username;
  final String email;
  final String userType;
  final bool isVerified;
  final String verificationStatus;
  final String? avatar;
  final String? profilePicture;
  final String agentAvailability;
  final String agentStatusNote;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.userType,
    required this.isVerified,
    required this.verificationStatus,
    this.avatar,
    this.profilePicture,
    this.agentAvailability = 'online',
    this.agentStatusNote = '',
  });

  factory User.fromJson(Map<String, dynamic> json) {
    debugPrint('DEBUG parsing User fromJson: $json');
    final normalizedUserType =
        (json['user_type'] ?? 'client').toString().trim().toLowerCase();
    return User(
      id: _parseInt(json['id']) ?? 0,
      username: json['username'] ?? 'Unknown',
      email: json['email'] ?? '',
      userType: normalizedUserType,
      isVerified: json['is_verified'] ?? false,
      verificationStatus: json['verification_status'] ?? 'none',
      avatar: json['avatar'] ?? json['profile_picture'],
      profilePicture: json['profile_picture'] ?? json['avatar'],
      agentAvailability: json['agent_availability'] ?? 'online',
      agentStatusNote: json['agent_status_note'] ?? '',
    );
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'user_type': userType,
      'is_verified': isVerified,
      'verification_status': verificationStatus,
      'avatar': avatar,
      'profile_picture': profilePicture,
      'agent_availability': agentAvailability,
      'agent_status_note': agentStatusNote,
    };
  }

  bool get isStaff => userType.toLowerCase() == 'staff';
  bool get isAgent => userType.toLowerCase() == 'agent';
  bool get isPlayer => userType.toLowerCase() == 'player';
}
