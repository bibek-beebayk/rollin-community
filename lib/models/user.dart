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
  final String? profileThumbnail;
  final bool hasUsablePassword;
  final bool needsUsernameSetup;
  final String agentAvailability;
  final String agentStatusNote;
  final DateTime? joinedAt;
  final String? headline;
  final String connectionStatus;
  final bool canConnect;
  final bool canDisconnect;
  final bool canChat;
  final String? primaryAction;
  final String? secondaryAction;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.userType,
    required this.isVerified,
    required this.verificationStatus,
    this.avatar,
    this.profilePicture,
    this.profileThumbnail,
    this.hasUsablePassword = true,
    this.needsUsernameSetup = false,
    this.agentAvailability = 'online',
    this.agentStatusNote = '',
    this.joinedAt,
    this.headline,
    this.connectionStatus = 'none',
    this.canConnect = false,
    this.canDisconnect = false,
    this.canChat = false,
    this.primaryAction,
    this.secondaryAction,
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
      profileThumbnail: json['profile_thumbnail'],
      hasUsablePassword: json['has_usable_password'] ?? true,
      needsUsernameSetup: json['needs_username_setup'] ?? false,
      agentAvailability: json['agent_availability'] ?? 'online',
      agentStatusNote: json['agent_status_note'] ?? '',
      joinedAt: json['joined_at'] != null
          ? DateTime.tryParse(json['joined_at'].toString())
          : null,
      headline: json['headline']?.toString(),
      connectionStatus: (json['connection_status'] ?? 'none').toString(),
      canConnect: json['can_connect'] ?? false,
      canDisconnect: json['can_disconnect'] ?? false,
      canChat: json['can_chat'] ?? false,
      primaryAction: json['primary_action']?.toString(),
      secondaryAction: json['secondary_action']?.toString(),
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
      'profile_thumbnail': profileThumbnail,
      'has_usable_password': hasUsablePassword,
      'needs_username_setup': needsUsernameSetup,
      'agent_availability': agentAvailability,
      'agent_status_note': agentStatusNote,
      'joined_at': joinedAt?.toIso8601String(),
      'headline': headline,
      'connection_status': connectionStatus,
      'can_connect': canConnect,
      'can_disconnect': canDisconnect,
      'can_chat': canChat,
      'primary_action': primaryAction,
      'secondary_action': secondaryAction,
    };
  }

  bool get isStaff => userType.toLowerCase() == 'staff';
  bool get isAgent => userType.toLowerCase() == 'agent';
  bool get isPlayer => userType.toLowerCase() == 'player';
}
