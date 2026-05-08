import 'user.dart';

class PostComment {
  final int id;
  final int? parentId;
  final String content;
  final User? author;
  final List<PostComment> replies;
  final DateTime createdAt;

  const PostComment({
    required this.id,
    required this.content,
    required this.createdAt,
    this.parentId,
    this.author,
    this.replies = const [],
  });

  factory PostComment.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value, {int fallback = 0}) {
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? fallback;
      return fallback;
    }

    int? parseNullableInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      return null;
    }

    final repliesRaw = json['replies'];
    final replies = <PostComment>[];
    if (repliesRaw is List) {
      for (final item in repliesRaw) {
        if (item is Map<String, dynamic>) {
          replies.add(PostComment.fromJson(item));
        }
      }
    }

    return PostComment(
      id: parseInt(json['id']),
      parentId: parseNullableInt(json['parent']),
      content: (json['content'] ?? '').toString(),
      author: json['author'] is Map<String, dynamic>
          ? User.fromJson(json['author'] as Map<String, dynamic>)
          : null,
      replies: replies,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

