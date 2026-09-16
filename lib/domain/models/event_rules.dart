class EventRulesTemplate {
  const EventRulesTemplate({
    required this.id,
    required this.organizerId,
    required this.title,
    required this.body,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String organizerId;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime? updatedAt;

  String get shortBody {
    final text = body.trim();
    if (text.length <= 90) return text;
    return '${text.substring(0, 87).trimRight()}…';
  }

  factory EventRulesTemplate.fromJson(Map<String, dynamic> json) {
    return EventRulesTemplate(
      id: json['id'] as String,
      organizerId: json['organizer_id'] as String,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'] as String),
    );
  }
}
