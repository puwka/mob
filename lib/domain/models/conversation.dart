enum ConversationType {
  market,
  clan,
  user;

  static ConversationType fromString(String value) {
    return ConversationType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ConversationType.user,
    );
  }

  String get folderLabel => switch (this) {
        ConversationType.market => 'Барахолка',
        ConversationType.clan => 'Клан',
        ConversationType.user => 'Личные',
      };
}

enum ClanChatChannel {
  general,
  officers;

  static ClanChatChannel? fromString(String? value) {
    if (value == null || value.isEmpty) return null;
    return ClanChatChannel.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ClanChatChannel.general,
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.text,
    required this.createdAt,
    this.editedAt,
    this.deletedAt,
    this.senderNickname,
    this.pending = false,
    this.failed = false,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String text;
  final DateTime createdAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final String? senderNickname;
  final bool pending;
  final bool failed;

  bool get isDeleted => deletedAt != null;

  ChatMessage copyWith({
    bool? pending,
    bool? failed,
    String? id,
    String? senderNickname,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      conversationId: conversationId,
      senderId: senderId,
      text: text,
      createdAt: createdAt,
      editedAt: editedAt,
      deletedAt: deletedAt,
      senderNickname: senderNickname ?? this.senderNickname,
      pending: pending ?? this.pending,
      failed: failed ?? this.failed,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    String? nick;
    final sender = json['sender'];
    if (sender is Map) {
      nick = sender['nickname'] as String?;
    }

    return ChatMessage(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: json['sender_id'] as String,
      text: json['text'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      editedAt: json['edited_at'] == null
          ? null
          : DateTime.parse(json['edited_at'] as String),
      deletedAt: json['deleted_at'] == null
          ? null
          : DateTime.parse(json['deleted_at'] as String),
      senderNickname: nick,
    );
  }
}

class ConversationPreview {
  const ConversationPreview({
    required this.id,
    required this.type,
    this.title,
    this.listingId,
    this.clanId,
    this.clanChannel,
    required this.createdAt,
    required this.updatedAt,
    this.lastMessageText,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.peerUserId,
    this.peerNickname,
    this.peerAvatarUrl,
    this.peerLastSeenAt,
    this.listingTitle,
    this.listingPrice,
    this.listingCoverUrl,
  });

  final String id;
  final ConversationType type;
  final String? title;
  final String? listingId;
  final String? clanId;
  final ClanChatChannel? clanChannel;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? lastMessageText;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final String? peerUserId;
  final String? peerNickname;
  final String? peerAvatarUrl;
  final DateTime? peerLastSeenAt;
  final String? listingTitle;
  final double? listingPrice;
  final String? listingCoverUrl;

  String get displayTitle {
    if (type == ConversationType.market) {
      return listingTitle ?? title ?? 'Объявление';
    }
    if (type == ConversationType.clan) {
      if (clanChannel == ClanChatChannel.officers) {
        return 'Руководство';
      }
      return 'Общий чат';
    }
    return peerNickname ?? title ?? 'Диалог';
  }

  bool get hasUnread => unreadCount > 0;

  ConversationPreview copyWith({
    String? lastMessageText,
    DateTime? lastMessageAt,
    int? unreadCount,
    DateTime? updatedAt,
  }) {
    return ConversationPreview(
      id: id,
      type: type,
      title: title,
      listingId: listingId,
      clanId: clanId,
      clanChannel: clanChannel,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastMessageText: lastMessageText ?? this.lastMessageText,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      peerUserId: peerUserId,
      peerNickname: peerNickname,
      peerAvatarUrl: peerAvatarUrl,
      peerLastSeenAt: peerLastSeenAt,
      listingTitle: listingTitle,
      listingPrice: listingPrice,
      listingCoverUrl: listingCoverUrl,
    );
  }
}

class ConversationDetail {
  const ConversationDetail({
    required this.id,
    required this.type,
    this.title,
    this.listingId,
    this.clanId,
    this.clanChannel,
    required this.createdAt,
    required this.updatedAt,
    this.listingTitle,
    this.listingPrice,
    this.listingCoverUrl,
    this.peerNickname,
    this.peerAvatarUrl,
    this.peerUserId,
    this.peerLastSeenAt,
  });

  final String id;
  final ConversationType type;
  final String? title;
  final String? listingId;
  final String? clanId;
  final ClanChatChannel? clanChannel;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? listingTitle;
  final double? listingPrice;
  final String? listingCoverUrl;
  final String? peerNickname;
  final String? peerAvatarUrl;
  final String? peerUserId;
  final DateTime? peerLastSeenAt;

  String get displayTitle {
    if (type == ConversationType.market) {
      return listingTitle ?? title ?? 'Объявление';
    }
    if (type == ConversationType.clan) {
      if (clanChannel == ClanChatChannel.officers) {
        return 'Руководство';
      }
      return 'Общий чат';
    }
    return peerNickname ?? title ?? 'Диалог';
  }
}
