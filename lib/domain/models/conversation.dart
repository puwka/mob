import 'clan.dart';
import '../../core/utils/date_time_parse.dart';

enum ConversationType {
  market,
  dating,
  clan,
  user,
  city,
  event;

  static ConversationType fromString(String value) {
    return ConversationType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ConversationType.user,
    );
  }

  String get folderLabel => switch (this) {
        ConversationType.market => 'Барахолка',
        ConversationType.dating => 'Дейтинг',
        ConversationType.clan => 'Клан',
        ConversationType.user => 'Личные',
        ConversationType.city => 'Город',
        ConversationType.event => 'Мероприятия',
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

class ChatMuteInfo {
  const ChatMuteInfo({
    required this.conversationId,
    this.mutedUntil,
    this.reason,
    required this.createdAt,
  });

  final String conversationId;
  final DateTime? mutedUntil;
  final String? reason;
  final DateTime createdAt;

  bool get isActive =>
      mutedUntil == null || mutedUntil!.isAfter(DateTime.now());

  factory ChatMuteInfo.fromJson(Map<String, dynamic> json) {
    return ChatMuteInfo(
      conversationId: '${json['conversation_id']}',
      mutedUntil: json['muted_until'] == null
          ? null
          : tryParseSupabaseDateTime(json['muted_until']),
      reason: json['reason'] as String?,
      createdAt:
          tryParseSupabaseDateTime(json['created_at']) ?? DateTime.now().toUtc(),
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
    this.messageType = ChatMessageType.text,
    this.audioUrl,
    this.audioDurationMs,
    this.imageUrl,
    this.imageUrls = const [],
    this.replyToMessageId,
    this.replyTo,
    this.senderNickname,
    this.senderAvatarUrl,
    this.senderClanRole,
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
  final ChatMessageType messageType;
  final String? audioUrl;
  final int? audioDurationMs;
  final String? imageUrl;
  final List<String> imageUrls;
  final String? replyToMessageId;
  final ChatReplyPreview? replyTo;
  final String? senderNickname;
  final String? senderAvatarUrl;
  final ClanRole? senderClanRole;
  final bool pending;
  final bool failed;

  bool get isDeleted => deletedAt != null;
  bool get isVoice => messageType == ChatMessageType.voice;
  bool get isImage => messageType == ChatMessageType.image;

  /// Prefer album column; fall back to legacy single `image_url`.
  List<String> get resolvedImageUrls {
    final fromAlbum = [
      for (final u in imageUrls)
        if (u.trim().isNotEmpty) u.trim(),
    ];
    if (fromAlbum.isNotEmpty) return fromAlbum;
    final single = imageUrl?.trim();
    if (single != null && single.isNotEmpty) return [single];
    return const [];
  }

  String get displaySenderName {
    final n = senderNickname?.trim();
    if (n != null && n.isNotEmpty) return n;
    return 'Игрок';
  }

  String get previewText {
    if (isDeleted) return 'Сообщение удалено';
    if (isVoice) return 'Голосовое сообщение';
    if (isImage) {
      final n = resolvedImageUrls.length;
      if (n > 1) return '$n фото';
      return 'Фото';
    }
    return text;
  }

  ChatMessage copyWith({
    bool? pending,
    bool? failed,
    String? id,
    String? senderNickname,
    String? senderAvatarUrl,
    ClanRole? senderClanRole,
    bool clearSenderClanRole = false,
    String? audioUrl,
    int? audioDurationMs,
    String? imageUrl,
    List<String>? imageUrls,
    ChatMessageType? messageType,
    String? text,
    String? replyToMessageId,
    ChatReplyPreview? replyTo,
    bool clearReplyTo = false,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      conversationId: conversationId,
      senderId: senderId,
      text: text ?? this.text,
      createdAt: createdAt,
      editedAt: editedAt,
      deletedAt: deletedAt,
      messageType: messageType ?? this.messageType,
      audioUrl: audioUrl ?? this.audioUrl,
      audioDurationMs: audioDurationMs ?? this.audioDurationMs,
      imageUrl: imageUrl ?? this.imageUrl,
      imageUrls: imageUrls ?? this.imageUrls,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      replyTo: clearReplyTo ? null : (replyTo ?? this.replyTo),
      senderNickname: senderNickname ?? this.senderNickname,
      senderAvatarUrl: senderAvatarUrl ?? this.senderAvatarUrl,
      senderClanRole: clearSenderClanRole
          ? null
          : (senderClanRole ?? this.senderClanRole),
      pending: pending ?? this.pending,
      failed: failed ?? this.failed,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    String? nick;
    String? avatar;
    final sender = json['sender'];
    if (sender is Map) {
      nick = sender['nickname'] as String?;
      avatar = sender['avatar_url'] as String?;
    }
    nick ??= json['sender_nickname'] as String?;
    avatar ??= json['sender_avatar_url'] as String?;

    ClanRole? clanRole;
    final roleRaw = json['sender_clan_role'] as String?;
    if (roleRaw != null && roleRaw.isNotEmpty) {
      clanRole = ClanRole.fromString(roleRaw);
    }

    ChatReplyPreview? reply;
    final replyRaw = json['reply_to'];
    if (replyRaw is Map) {
      reply = ChatReplyPreview.fromJson(Map<String, dynamic>.from(replyRaw));
    }

    final urls = <String>[];
    final rawUrls = json['image_urls'];
    if (rawUrls is List) {
      for (final item in rawUrls) {
        final s = item?.toString().trim();
        if (s != null && s.isNotEmpty) urls.add(s);
      }
    }

    return ChatMessage(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: json['sender_id'] as String,
      text: json['text'] as String? ?? '',
      createdAt: parseSupabaseDateTime(json['created_at']),
      editedAt: json['edited_at'] == null
          ? null
          : parseSupabaseDateTime(json['edited_at']),
      deletedAt: json['deleted_at'] == null
          ? null
          : parseSupabaseDateTime(json['deleted_at']),
      messageType: ChatMessageType.fromString(
        json['message_type'] as String? ?? 'text',
      ),
      audioUrl: json['audio_url'] as String?,
      audioDurationMs: (json['audio_duration_ms'] as num?)?.toInt(),
      imageUrl: json['image_url'] as String?,
      imageUrls: urls,
      replyToMessageId: json['reply_to_message_id'] as String?,
      replyTo: reply,
      senderNickname: nick,
      senderAvatarUrl: avatar,
      senderClanRole: clanRole,
    );
  }
}

class ChatReplyPreview {
  const ChatReplyPreview({
    required this.id,
    required this.senderId,
    required this.text,
    required this.messageType,
    this.deletedAt,
    this.senderNickname,
    this.imageCount = 1,
  });

  final String id;
  final String senderId;
  final String text;
  final ChatMessageType messageType;
  final DateTime? deletedAt;
  final String? senderNickname;
  final int imageCount;

  bool get isDeleted => deletedAt != null;

  String get displaySenderName {
    final n = senderNickname?.trim();
    if (n != null && n.isNotEmpty) return n;
    return 'Игрок';
  }

  String get previewText {
    if (isDeleted) return 'Сообщение удалено';
    if (messageType == ChatMessageType.voice) return 'Голосовое сообщение';
    if (messageType == ChatMessageType.image) {
      if (imageCount > 1) return '$imageCount фото';
      return 'Фото';
    }
    final t = text.trim();
    if (t.isEmpty) return 'Сообщение';
    return t;
  }

  factory ChatReplyPreview.fromJson(Map<String, dynamic> json) {
    String? nick;
    final sender = json['sender'];
    if (sender is Map) {
      nick = sender['nickname'] as String?;
    }
    nick ??= json['sender_nickname'] as String?;

    var imageCount = 1;
    final rawUrls = json['image_urls'];
    if (rawUrls is List) {
      final n = rawUrls.where((e) => e?.toString().trim().isNotEmpty == true).length;
      if (n > 0) imageCount = n;
    } else if (json['image_count'] is num) {
      imageCount = (json['image_count'] as num).toInt().clamp(1, 10);
    }

    return ChatReplyPreview(
      id: json['id'] as String,
      senderId: json['sender_id'] as String? ?? '',
      text: json['text'] as String? ?? '',
      messageType: ChatMessageType.fromString(
        json['message_type'] as String? ?? 'text',
      ),
      deletedAt: json['deleted_at'] == null
          ? null
          : tryParseSupabaseDateTime(json['deleted_at']),
      senderNickname: nick,
      imageCount: imageCount,
    );
  }

  factory ChatReplyPreview.fromMessage(ChatMessage message) {
    final n = message.resolvedImageUrls.length;
    return ChatReplyPreview(
      id: message.id,
      senderId: message.senderId,
      text: message.text,
      messageType: message.messageType,
      deletedAt: message.deletedAt,
      senderNickname: message.senderNickname,
      imageCount: n > 0 ? n : 1,
    );
  }
}

enum ChatMessageType {
  text,
  voice,
  image;

  static ChatMessageType fromString(String value) {
    return ChatMessageType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ChatMessageType.text,
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
      return peerNickname ?? listingTitle ?? title ?? 'Объявление';
    }
    if (type == ConversationType.clan) {
      if (clanChannel == ClanChatChannel.officers) {
        return 'Руководство';
      }
      return 'Общий чат';
    }
    if (type == ConversationType.city) {
      return title ?? 'Чат города';
    }
    if (type == ConversationType.event) {
      return title ?? 'Мероприятие';
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
      return peerNickname ?? listingTitle ?? title ?? 'Объявление';
    }
    if (type == ConversationType.clan) {
      if (clanChannel == ClanChatChannel.officers) {
        return 'Руководство';
      }
      return 'Общий чат';
    }
    if (type == ConversationType.city) {
      return title ?? 'Чат города';
    }
    if (type == ConversationType.event) {
      return title ?? 'Мероприятие';
    }
    return peerNickname ?? title ?? 'Диалог';
  }
}

class ConversationParticipant {
  const ConversationParticipant({
    required this.userId,
    required this.nickname,
    this.avatarUrl,
    this.clanRole,
  });

  final String userId;
  final String nickname;
  final String? avatarUrl;
  final ClanRole? clanRole;

  String? get roleLabel => clanRole?.labelRu;
}
