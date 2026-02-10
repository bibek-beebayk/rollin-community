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

  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      id: json['id'] ?? 0,
      title: json['title'] ?? 'Untitled Event',
      description: json['description'] ?? '',
      bannerImage: json['banner_image'],
      startDate: json['start_date'] != null
          ? DateTime.tryParse(json['start_date'])
          : null,
      endDate:
          json['end_date'] != null ? DateTime.tryParse(json['end_date']) : null,
      isActive: json['is_active'] ?? false,
    );
  }
}
