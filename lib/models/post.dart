import 'user.dart';

class PostImageItem {
  final int id;
  final String imageUrl;
  final int order;

  const PostImageItem({
    required this.id,
    required this.imageUrl,
    required this.order,
  });

  factory PostImageItem.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value, {int fallback = 0}) {
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? fallback;
      return fallback;
    }

    return PostImageItem(
      id: parseInt(json['id']),
      imageUrl: (json['image'] ?? '').toString(),
      order: parseInt(json['order']),
    );
  }
}

class Post {
  final int id;
  final String title;
  final String content;
  final String? image;
  final String? video;
  final String? link;
  final String visibility;
  final User? author;
  final List<String> images;
  final List<PostImageItem> imageItems;
  final int likeCount;
  final int commentCount;
  final bool isLiked;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Post({
    required this.id,
    required this.title,
    required this.content,
    this.image,
    this.video,
    this.link,
    this.visibility = 'public',
    this.author,
    this.images = const [],
    this.imageItems = const [],
    this.likeCount = 0,
    this.commentCount = 0,
    this.isLiked = false,
    required this.createdAt,
    this.updatedAt,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    // Build image items + image URLs from nested 'images' array.
    List<PostImageItem> imageItems = [];
    List<String> imageUrls = [];
    if (json['images'] != null && json['images'] is List) {
      imageItems = (json['images'] as List)
          .whereType<Map>()
          .map((img) => PostImageItem.fromJson(Map<String, dynamic>.from(img)))
          .where((img) => img.imageUrl.trim().isNotEmpty)
          .toList();
      imageUrls = imageItems
          .map((img) => img.imageUrl)
          .where((url) => url.isNotEmpty)
          .toList();
    }

    // Fallback: if no images array but legacy single image exists, use it
    if (imageUrls.isEmpty && json['image'] != null && json['image'].toString().trim().isNotEmpty) {
      imageUrls = [json['image'].toString()];
    }

    return Post(
      id: _parseInt(json['id'], fallback: 0),
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      image: json['image'],
      video: json['video'],
      link: json['link'],
      visibility: json['visibility'] ?? 'public',
      author: json['author'] != null ? User.fromJson(json['author']) : null,
      images: imageUrls,
      imageItems: imageItems,
      likeCount: _parseInt(json['like_count'], fallback: 0),
      commentCount: _parseInt(json['comment_count'], fallback: 0),
      isLiked: json['is_liked'] == true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
    );
  }

  static int _parseInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  Post copyWith({
    int? likeCount,
    int? commentCount,
    bool? isLiked,
  }) {
    return Post(
      id: id,
      title: title,
      content: content,
      image: image,
      video: video,
      link: link,
      visibility: visibility,
      author: author,
      images: images,
      imageItems: imageItems,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      isLiked: isLiked ?? this.isLiked,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Whether the current user is the author (pass user id to check)
  bool isAuthor(int? userId) => author?.id == userId;
}
