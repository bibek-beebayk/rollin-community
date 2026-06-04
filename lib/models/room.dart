import 'user.dart';

class Room {
  final int id;
  final String name;
  final String roomType;
  final String slug;
  final String? description;
  final int onlineCount;
  final bool isPrivate;
  // For support rooms
  final User? staff;
  final bool isActive;
  final int? queue; // ID of the support queue/room this chat belongs to
  final String? queueName;
  final bool canSwitchStation;
  final User? counterpart;
  final User? groupAdmin;
  final String? groupDescription;
  final int groupMemberCount;
  final bool userIsGroupAdmin;
  final DateTime? lastActivity;
  final int? lastMessageSenderId;
  final bool isMessageRequest;
  final String messageRequestDirection;
  final String directRequestStatus;
  final User? directRequestInitiator;
  int unreadCount;

  Room({
    required this.id,
    required this.name,
    this.roomType = 'support',
    required this.slug,
    this.description,
    this.onlineCount = 0,
    this.isPrivate = false,
    this.staff,
    this.isActive = false,
    this.queue,
    this.queueName,
    this.canSwitchStation = false,
    this.counterpart,
    this.groupAdmin,
    this.groupDescription,
    this.groupMemberCount = 0,
    this.userIsGroupAdmin = false,
    this.lastActivity,
    this.lastMessageSenderId,
    this.isMessageRequest = false,
    this.messageRequestDirection = 'none',
    this.directRequestStatus = 'accepted',
    this.directRequestInitiator,
    this.unreadCount = 0,
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    // DEBUG: Print raw JSON to find the correct "online" field
    // debugPrint('ROOM JSON: $json');

    return Room(
      id: json['id'] ?? 0,
      name: json['name'] ?? 'Unknown Room',
      roomType: json['room_type'] ?? 'support',
      slug: json['slug'] ?? '',
      description: json['description'],
      onlineCount: json['online_count'] ?? 0,
      isPrivate: json['is_private'] ?? false,
      staff: json['staff'] != null ? User.fromJson(json['staff']) : null,
      isActive: json['is_active'] ?? false,
      queue: json['queue'],
      queueName: json['queue_name'],
      canSwitchStation: json['can_switch_station'] ?? false,
      counterpart: json['counterpart'] != null
          ? User.fromJson(json['counterpart'])
          : null,
      groupAdmin: json['group_admin'] != null
          ? User.fromJson(json['group_admin'])
          : null,
      groupDescription: json['group_description'],
      groupMemberCount: json['group_member_count'] ?? 0,
      userIsGroupAdmin: json['user_is_group_admin'] ?? false,
      lastActivity: json['last_activity'] != null
          ? DateTime.tryParse(json['last_activity'])
          : null,
      lastMessageSenderId: json['last_message_sender_id'],
      isMessageRequest: json['is_message_request'] == true,
      messageRequestDirection:
          (json['message_request_direction'] ?? 'none').toString(),
      directRequestStatus:
          (json['direct_request_status'] ?? 'accepted').toString(),
      directRequestInitiator: json['direct_request_initiator'] != null
          ? User.fromJson(json['direct_request_initiator'])
          : null,
      unreadCount: json['unread_count'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'room_type': roomType,
      'slug': slug,
      'description': description,
      'online_count': onlineCount,
      'is_private': isPrivate,
      'staff': staff?.toJson(),
      'is_active': isActive,
      'queue_name': queueName,
      'can_switch_station': canSwitchStation,
      'counterpart': counterpart?.toJson(),
      'group_admin': groupAdmin?.toJson(),
      'group_description': groupDescription,
      'group_member_count': groupMemberCount,
      'user_is_group_admin': userIsGroupAdmin,
      'last_activity': lastActivity?.toIso8601String(),
      'last_message_sender_id': lastMessageSenderId,
      'is_message_request': isMessageRequest,
      'message_request_direction': messageRequestDirection,
      'direct_request_status': directRequestStatus,
      'direct_request_initiator': directRequestInitiator?.toJson(),
    };
  }
}
