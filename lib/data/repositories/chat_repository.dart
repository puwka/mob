import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/app_exception.dart';
import '../../core/utils/error_mapper.dart';
import '../../domain/models/conversation.dart';

class ChatRepository {
  ChatRepository(this._client);

  final SupabaseClient _client;

  static const _pageSize = 40;

  String? get _uid => _client.auth.currentUser?.id;

  Future<List<ConversationPreview>> fetchConversations({
    required ConversationType type,
  }) async {
    try {
      final uid = _uid;
      if (uid == null) throw const AppException('Требуется авторизация');

      final memberships = await _client
          .from('conversation_members')
          .select('conversation_id, last_read_at, hidden_at')
          .eq('user_id', uid)
          .isFilter('hidden_at', null)
          .timeout(const Duration(seconds: 15));

      final memberRows = memberships as List;
      if (memberRows.isEmpty) return const [];

      final convIds = <String>[];
      final lastRead = <String, DateTime?>{};
      for (final row in memberRows) {
        final map = Map<String, dynamic>.from(row as Map);
        final id = map['conversation_id'] as String;
        convIds.add(id);
        lastRead[id] = map['last_read_at'] == null
            ? null
            : DateTime.parse(map['last_read_at'] as String);
      }

      final convRows = await _client
          .from('conversations')
          .select(
            'id, type, title, listing_id, clan_id, clan_channel, created_at, updated_at',
          )
          .eq('type', type.name)
          .inFilter('id', convIds)
          .order('updated_at', ascending: false)
          .timeout(const Duration(seconds: 15));

      final previews = <ConversationPreview>[];
      for (final raw in convRows as List) {
        final c = Map<String, dynamic>.from(raw as Map);
        final id = c['id'] as String;

        String? lastText;
        DateTime? lastAt;
        try {
          final last = await _client
              .from('messages')
              .select('text, created_at, deleted_at, message_type')
              .eq('conversation_id', id)
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle()
              .timeout(const Duration(seconds: 8));
          if (last != null) {
            lastAt = DateTime.parse(last['created_at'] as String);
            if (last['deleted_at'] != null) {
              lastText = 'Сообщение удалено';
            } else if ((last['message_type'] as String?) == 'voice') {
              lastText = 'Голосовое сообщение';
            } else if ((last['message_type'] as String?) == 'image') {
              lastText = 'Фото';
            } else {
              lastText = last['text'] as String?;
            }
          }
        } catch (_) {}

        var unread = 0;
        try {
          final readAt = lastRead[id];
          var q = _client
              .from('messages')
              .select('id')
              .eq('conversation_id', id)
              .neq('sender_id', uid);
          if (readAt != null) {
            q = q.gt('created_at', readAt.toUtc().toIso8601String());
          }
          final unreadRows = await q.timeout(const Duration(seconds: 8));
          unread = (unreadRows as List).length;
        } catch (_) {}

        String? peerId;
        String? peerNick;
        String? peerAvatar;
        DateTime? peerLastSeen;
        String? listingTitle;
        double? listingPrice;
        String? listingCover;

        final convType = ConversationType.fromString(c['type'] as String);
        if (convType == ConversationType.user ||
            convType == ConversationType.market ||
            convType == ConversationType.dating) {
          try {
            final peers = await _client
                .from('conversation_members')
                .select('user_id')
                .eq('conversation_id', id)
                .neq('user_id', uid)
                .limit(1)
                .timeout(const Duration(seconds: 8));
            if ((peers as List).isNotEmpty) {
              peerId = (peers.first as Map)['user_id'] as String;
              final profile = await _client
                  .from('profiles')
                  .select('nickname, avatar_url, last_seen_at')
                  .eq('id', peerId)
                  .maybeSingle()
                  .timeout(const Duration(seconds: 8));
              peerNick = profile?['nickname'] as String?;
              peerAvatar = profile?['avatar_url'] as String?;
              final seen = profile?['last_seen_at'] as String?;
              if (seen != null) peerLastSeen = DateTime.parse(seen);
            }
          } catch (_) {}
        }

        final listingId = c['listing_id'] as String?;
        if (listingId != null) {
          try {
            final listing = await _client
                .from('listings')
                .select('title, price')
                .eq('id', listingId)
                .maybeSingle()
                .timeout(const Duration(seconds: 8));
            if (listing != null) {
              listingTitle = listing['title'] as String?;
              listingPrice = (listing['price'] as num?)?.toDouble();
            }
            final img = await _client
                .from('listing_images')
                .select('url')
                .eq('listing_id', listingId)
                .order('sort_order', ascending: true)
                .limit(1)
                .maybeSingle()
                .timeout(const Duration(seconds: 8));
            listingCover = img?['url'] as String?;
          } catch (_) {}
        }

        final channel = ClanChatChannel.fromString(c['clan_channel'] as String?);
        if (convType == ConversationType.clan ||
            convType == ConversationType.city) {
          peerNick = c['title'] as String?;
        }

        previews.add(
          ConversationPreview(
            id: id,
            type: convType,
            title: c['title'] as String?,
            listingId: listingId,
            clanId: c['clan_id'] as String?,
            clanChannel: channel,
            createdAt: DateTime.parse(c['created_at'] as String),
            updatedAt: DateTime.parse(c['updated_at'] as String),
            lastMessageText: lastText,
            lastMessageAt: lastAt,
            unreadCount: unread,
            peerUserId: peerId,
            peerNickname: peerNick,
            peerAvatarUrl: peerAvatar,
            peerLastSeenAt: peerLastSeen,
            listingTitle: listingTitle,
            listingPrice: listingPrice,
            listingCoverUrl: listingCover,
          ),
        );
      }

      if (type == ConversationType.clan) {
        previews.sort((a, b) {
          final aRank = a.clanChannel == ClanChatChannel.officers ? 1 : 0;
          final bRank = b.clanChannel == ClanChatChannel.officers ? 1 : 0;
          if (aRank != bRank) return aRank.compareTo(bRank);
          final aAt = a.lastMessageAt ?? a.updatedAt;
          final bAt = b.lastMessageAt ?? b.updatedAt;
          return bAt.compareTo(aAt);
        });
      } else {
        previews.sort((a, b) {
          final aAt = a.lastMessageAt ?? a.updatedAt;
          final bAt = b.lastMessageAt ?? b.updatedAt;
          return bAt.compareTo(aAt);
        });
      }
      return previews;
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<ConversationDetail> fetchConversation(String id) async {
    try {
      final uid = _uid;
      if (uid == null) throw const AppException('Требуется авторизация');

      final row = await _client
          .from('conversations')
          .select(
            'id, type, title, listing_id, clan_id, clan_channel, created_at, updated_at',
          )
          .eq('id', id)
          .single()
          .timeout(const Duration(seconds: 12));

      final c = Map<String, dynamic>.from(row);
      final type = ConversationType.fromString(c['type'] as String);
      final channel = ClanChatChannel.fromString(c['clan_channel'] as String?);

      String? peerNick;
      String? peerAvatar;
      String? peerUserId;
      DateTime? peerLastSeen;
      String? listingTitle;
      double? listingPrice;
      String? listingCover;

      if (type == ConversationType.user ||
          type == ConversationType.market ||
          type == ConversationType.dating) {
        try {
          final peers = await _client
              .from('conversation_members')
              .select('user_id')
              .eq('conversation_id', id)
              .neq('user_id', uid)
              .limit(1);
          if ((peers as List).isNotEmpty) {
            peerUserId = (peers.first as Map)['user_id'] as String?;
            if (peerUserId != null) {
              final profile = await _client
                  .from('profiles')
                  .select('nickname, avatar_url, last_seen_at')
                  .eq('id', peerUserId)
                  .maybeSingle();
              peerNick = profile?['nickname'] as String?;
              peerAvatar = profile?['avatar_url'] as String?;
              final seen = profile?['last_seen_at'] as String?;
              if (seen != null) peerLastSeen = DateTime.parse(seen);
            }
          }
        } catch (_) {}
      }

      final listingId = c['listing_id'] as String?;
      if (listingId != null) {
        try {
          final listing = await _client
              .from('listings')
              .select('title, price')
              .eq('id', listingId)
              .maybeSingle();
          if (listing != null) {
            listingTitle = listing['title'] as String?;
            listingPrice = (listing['price'] as num?)?.toDouble();
          }
          final img = await _client
              .from('listing_images')
              .select('url')
              .eq('listing_id', listingId)
              .order('sort_order', ascending: true)
              .limit(1)
              .maybeSingle();
          listingCover = img?['url'] as String?;
        } catch (_) {}
      }

      return ConversationDetail(
        id: id,
        type: type,
        title: c['title'] as String?,
        listingId: listingId,
        clanId: c['clan_id'] as String?,
        clanChannel: channel,
        createdAt: DateTime.parse(c['created_at'] as String),
        updatedAt: DateTime.parse(c['updated_at'] as String),
        listingTitle: listingTitle,
        listingPrice: listingPrice,
        listingCoverUrl: listingCover,
        peerNickname: peerNick ?? (type == ConversationType.clan ? c['title'] as String? : null),
        peerAvatarUrl: peerAvatar,
        peerUserId: peerUserId,
        peerLastSeenAt: peerLastSeen,
      );
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<List<ChatMessage>> fetchMessages({
    required String conversationId,
    DateTime? before,
  }) async {
    try {
      var query = _client
          .from('messages')
          .select(
            'id, conversation_id, sender_id, text, created_at, edited_at, deleted_at, '
            'message_type, audio_url, audio_duration_ms, image_url, '
            'sender:profiles!messages_sender_id_fkey(nickname, avatar_url)',
          )
          .eq('conversation_id', conversationId);

      if (before != null) {
        query = query.lt('created_at', before.toUtc().toIso8601String());
      }

      final rows = await query
          .order('created_at', ascending: false)
          .limit(_pageSize)
          .timeout(const Duration(seconds: 15));

      var list = (rows as List)
          .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList()
          .reversed
          .toList();

      list = await _enrichSenders(list);
      return list;
    } catch (e) {
      // Fallback without embed if FK hint fails
      try {
        var query = _client
            .from('messages')
            .select(
              'id, conversation_id, sender_id, text, created_at, edited_at, deleted_at, '
              'message_type, audio_url, audio_duration_ms, image_url',
            )
            .eq('conversation_id', conversationId);
        if (before != null) {
          query = query.lt('created_at', before.toUtc().toIso8601String());
        }
        final rows = await query
            .order('created_at', ascending: false)
            .limit(_pageSize)
            .timeout(const Duration(seconds: 15));
        final list = (rows as List)
            .map(
              (e) => ChatMessage.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList()
            .reversed
            .toList();
        return _enrichSenders(list);
      } catch (e2) {
        throw AppException(ErrorMapper.map(e2));
      }
    }
  }

  Future<ChatMessage> enrichSender(ChatMessage message) async {
    if (message.senderNickname != null &&
        message.senderNickname!.isNotEmpty &&
        message.senderAvatarUrl != null) {
      return message;
    }
    final enriched = await _enrichSenders([message]);
    return enriched.isEmpty ? message : enriched.first;
  }

  Future<List<ChatMessage>> _enrichSenders(List<ChatMessage> messages) async {
    final needIds = <String>{};
    for (final m in messages) {
      if (m.senderNickname == null ||
          m.senderNickname!.isEmpty ||
          m.senderAvatarUrl == null) {
        needIds.add(m.senderId);
      }
    }
    if (needIds.isEmpty) return messages;

    try {
      final rows = await _client
          .from('profiles')
          .select('id, nickname, avatar_url')
          .inFilter('id', needIds.toList())
          .timeout(const Duration(seconds: 10));
      final byId = <String, Map<String, dynamic>>{};
      for (final raw in rows as List) {
        final map = Map<String, dynamic>.from(raw as Map);
        byId[map['id'] as String] = map;
      }
      return [
        for (final m in messages)
          if (byId.containsKey(m.senderId))
            m.copyWith(
              senderNickname: m.senderNickname?.isNotEmpty == true
                  ? m.senderNickname
                  : byId[m.senderId]!['nickname'] as String?,
              senderAvatarUrl: m.senderAvatarUrl ??
                  byId[m.senderId]!['avatar_url'] as String?,
            )
          else
            m,
      ];
    } catch (_) {
      return messages;
    }
  }

  Future<Map<ConversationType, int>> fetchUnreadByType() async {
    try {
      final rows = await _client
          .rpc('conversation_unread_by_type')
          .timeout(const Duration(seconds: 12));
      final map = <ConversationType, int>{
        for (final t in ConversationType.values) t: 0,
      };
      for (final raw in rows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final type = ConversationType.fromString(row['type'] as String? ?? '');
        map[type] = (row['unread_count'] as num?)?.toInt() ?? 0;
      }
      return map;
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<String> openMarketChat(String listingId) async {
    try {
      final result = await _client.rpc(
        'open_market_chat',
        params: {'p_listing_id': listingId},
      );
      return result as String;
    } catch (e) {
      throw AppException(_mapChatError(e));
    }
  }

  Future<String> openUserChat(String otherUserId) async {
    try {
      final result = await _client.rpc(
        'open_user_chat',
        params: {'p_other_user_id': otherUserId},
      );
      return result as String;
    } catch (e) {
      throw AppException(_mapChatError(e));
    }
  }

  Future<String> openClanChat(String clanId) async {
    try {
      final result = await _client.rpc(
        'open_clan_chat',
        params: {'p_clan_id': clanId},
      );
      return result as String;
    } catch (e) {
      throw AppException(_mapChatError(e));
    }
  }

  Future<String> openClanOfficersChat(String clanId) async {
    try {
      final result = await _client.rpc(
        'open_clan_officers_chat',
        params: {'p_clan_id': clanId},
      );
      return result as String;
    } catch (e) {
      throw AppException(_mapChatError(e));
    }
  }

  Future<String> openCityChat() async {
    try {
      final result = await _client.rpc('open_city_chat');
      return result as String;
    } catch (e) {
      throw AppException(_mapChatError(e));
    }
  }

  Future<List<String>> fetchMyClanIds() async {
    try {
      final uid = _uid;
      if (uid == null) return const [];
      final rows = await _client
          .from('clan_members')
          .select('clan_id')
          .eq('user_id', uid);
      return [
        for (final row in rows as List)
          (row as Map)['clan_id'] as String,
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<ChatMuteInfo?> fetchMyMute(String conversationId) async {
    try {
      final raw = await _client
          .rpc('get_my_chat_mute', params: {'p_conversation_id': conversationId})
          .timeout(const Duration(seconds: 8));
      if (raw == null) return null;
      final map = Map<String, dynamic>.from(raw as Map);
      return ChatMuteInfo.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Future<ChatMessage> sendMessage({
    required String conversationId,
    required String text,
  }) async {
    try {
      final row = await _client.rpc(
        'send_chat_message',
        params: {
          'p_conversation_id': conversationId,
          'p_text': text,
          'p_message_type': 'text',
        },
      );
      return ChatMessage.fromJson(Map<String, dynamic>.from(row as Map));
    } catch (e) {
      throw AppException(_mapChatError(e));
    }
  }

  Future<ChatMessage> sendVoiceMessage({
    required String conversationId,
    required String audioUrl,
    required int durationMs,
  }) async {
    try {
      final row = await _client.rpc(
        'send_chat_message',
        params: {
          'p_conversation_id': conversationId,
          'p_text': null,
          'p_message_type': 'voice',
          'p_audio_url': audioUrl,
          'p_audio_duration_ms': durationMs,
        },
      );
      return ChatMessage.fromJson(Map<String, dynamic>.from(row as Map));
    } catch (e) {
      throw AppException(_mapChatError(e));
    }
  }

  Future<ChatMessage> sendImageMessage({
    required String conversationId,
    required String imageUrl,
  }) async {
    try {
      final row = await _client.rpc(
        'send_chat_message',
        params: {
          'p_conversation_id': conversationId,
          'p_text': null,
          'p_message_type': 'image',
          'p_image_url': imageUrl,
        },
      );
      return ChatMessage.fromJson(Map<String, dynamic>.from(row as Map));
    } catch (e) {
      throw AppException(_mapChatError(e));
    }
  }

  Future<void> hideConversation(String conversationId) async {
    try {
      await _client.rpc(
        'hide_conversation',
        params: {'p_conversation_id': conversationId},
      );
    } catch (e) {
      throw AppException(_mapChatError(e));
    }
  }

  Future<void> markRead(String conversationId) async {
    try {
      await _client.rpc(
        'mark_conversation_read',
        params: {'p_conversation_id': conversationId},
      );
    } catch (_) {}
  }

  RealtimeChannel subscribeMessages({
    required String conversationId,
    required void Function(ChatMessage message) onInsert,
  }) {
    final channel = _client.channel('messages-$conversationId');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            try {
              final msg = ChatMessage.fromJson(
                Map<String, dynamic>.from(payload.newRecord),
              );
              onInsert(msg);
            } catch (_) {}
          },
        )
        .subscribe();
    return channel;
  }

  RealtimeChannel subscribeConversationsInbox({
    required void Function() onChange,
  }) {
    final channel = _client.channel('inbox-updates');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
          callback: (_) => onChange(),
        )
        .subscribe();
    return channel;
  }

  String _mapChatError(Object e) {
    final raw = e.toString().toUpperCase();
    if (raw.contains('FLOOD')) {
      return 'Слишком много сообщений. Подождите немного.';
    }
    if (raw.contains('CANNOT_CHAT_SELF')) {
      return 'Нельзя написать самому себе';
    }
    if (raw.contains('CITY_REQUIRED') || raw.contains('INVALID_CITY')) {
      return 'Укажите город в профиле, чтобы открыть чат города';
    }
    if (raw.contains('NOT_CLAN_MEMBER')) {
      return 'Вы не состоите в этом клане';
    }
    if (raw.contains('CHAT_MUTED')) {
      return 'Вам запрещено писать в этот чат (мут)';
    }
    if (raw.contains('NOT_CLAN_OFFICER')) {
      return 'Чат руководства доступен командованию клана';
    }
    if (raw.contains('LISTING_NOT_FOUND')) {
      return 'Объявление недоступно';
    }
    if (raw.contains('EMPTY_AUDIO')) {
      return 'Не удалось записать голосовое сообщение';
    }
    if (raw.contains('EMPTY_IMAGE')) {
      return 'Не удалось отправить изображение';
    }
    if (raw.contains('CANNOT_HIDE_CONVERSATION')) {
      return 'Этот чат нельзя удалить';
    }
    if (raw.contains('INVALID_AUDIO_DURATION')) {
      return 'Голосовое слишком короткое или длинное';
    }
    if (raw.contains('EMPTY_MESSAGE')) {
      return 'Введите текст сообщения';
    }
    if (raw.contains('MESSAGE_TOO_LONG')) {
      return 'Сообщение слишком длинное';
    }
    if (raw.contains('NOT_MEMBER')) {
      return 'Нет доступа к этому диалогу';
    }
    return ErrorMapper.map(e);
  }
}
