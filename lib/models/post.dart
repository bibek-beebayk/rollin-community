import 'user.dart';

class Post {
  final int id;
  final String title;
  final String content;
  final String? image;
  final String? video;
  final String? link;
  final User? author;
  final DateTime createdAt;

  Post({
    required this.id,
    required this.title,
    required this.content,
    this.image,
    this.video,
    this.link,
    this.author,
    required this.createdAt,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'],
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      image: json['image'],
      video: json['video'],
      link: json['link'],
      author: json['author'] != null ? User.fromJson(json['author']) : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }
}
