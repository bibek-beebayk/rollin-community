import '../api/api_client.dart';

class Event {
  final int id;
  final String title;
  final String description;
  final String? bannerImage;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isActive;

  Event({
    required this.id,
    required this.title,
    required this.description,
    this.bannerImage,
    this.startDate,
    this.endDate,
    required this.isActive,
  });

  static String? _parseImageUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http')) return url;

    final baseUrl = ApiClient.baseUrl.endsWith('/')
        ? ApiClient.baseUrl.substring(0, ApiClient.baseUrl.length - 1)
        : ApiClient.baseUrl;

    final imagePath = url.startsWith('/') ? url : '/$url';
    return '$baseUrl$imagePath';
  }

  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      id: json['id'] ?? 0,
      title: json['title'] ?? 'Untitled Event',
      description: json['description'] ?? '',
      bannerImage: _parseImageUrl(json['poster'] as String?),
      startDate: json['start_date'] != null
          ? DateTime.tryParse(json['start_date'])
          : null,
      endDate:
          json['end_date'] != null ? DateTime.tryParse(json['end_date']) : null,
      isActive: json['is_active'] ?? false,
    );
  }
}
