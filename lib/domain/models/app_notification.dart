class AppNotificationKind {
  static const eventCreated = 'event_created';
  static const chatMessage = 'chat_message';
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.userId,
    required this.kind,
    required this.title,
    required this.body,
    this.eventId,
    this.conversationId,
    this.actorId,
    required this.createdAt,
    this.seenAt,
  });

  final String id;
  final String userId;
  final String kind;
  final String title;
  final String body;
  final String? eventId;
  final String? conversationId;
  final String? actorId;
  final DateTime createdAt;
  final DateTime? seenAt;

  bool get isEvent => kind == AppNotificationKind.eventCreated;
  bool get isChat => kind == AppNotificationKind.chatMessage;
  bool get isUnseen => seenAt == null;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      kind: json['kind'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      eventId: json['event_id'] as String?,
      conversationId: json['conversation_id'] as String?,
      actorId: json['actor_id'] as String?,
      createdAt: DateTime.tryParse('${json['created_at']}') ?? DateTime.now(),
      seenAt: json['seen_at'] == null
          ? null
          : DateTime.tryParse('${json['seen_at']}'),
    );
  }
}
