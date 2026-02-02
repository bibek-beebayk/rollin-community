import 'user.dart';

class Room {
  final int id;
  final String name;
  final String slug;
  final String? description;
  final int onlineCount;
  final bool isPrivate;
  // For support rooms
  final User? staff;
  final bool isActive;
  final int? queue; // ID of the support queue/room this chat belongs to

  Room({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    this.onlineCount = 0,
    this.isPrivate = false,
    this.staff,
    this.isActive = false,
    this.queue,
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    // DEBUG: Print raw JSON to find the correct "online" field
    print('ROOM JSON: $json');

    return Room(
      id: json['id'] ?? 0,
      name: json['name'] ?? 'Unknown Room',
      slug: json['slug'] ?? '',
      description: json['description'],
      onlineCount: json['online_count'] ?? 0,
      isPrivate: json['is_private'] ?? false,
      staff: json['staff'] != null ? User.fromJson(json['staff']) : null,
      isActive: json['is_active'] ?? false,
      queue: json['queue'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
      'description': description,
      'online_count': onlineCount,
      'is_private': isPrivate,
      'staff': staff?.toJson(),
      'is_active': isActive,
    };
  }
}
