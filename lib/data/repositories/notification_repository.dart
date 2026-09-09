import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/app_exception.dart';
import '../../core/utils/error_mapper.dart';
import '../../domain/models/app_notification.dart';

class NotificationRepository {
  NotificationRepository(this._client);

  final SupabaseClient _client;

  Future<List<AppNotification>> fetchPending({int limit = 20}) async {
    try {
      final rows = await _client.rpc(
        'get_pending_user_notifications',
        params: {'p_limit': limit},
      );
      return [
        for (final row in (rows as List))
          AppNotification.fromJson(Map<String, dynamic>.from(row as Map)),
      ];
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<void> markSeen(String id) async {
    try {
      await _client.rpc(
        'mark_user_notification_seen',
        params: {'p_id': id},
      );
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<bool> isConversationMuted(String conversationId) async {
    try {
      final muted = await _client.rpc(
        'get_conversation_notifications_muted',
        params: {'p_conversation_id': conversationId},
      );
      return muted == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setConversationMuted({
    required String conversationId,
    required bool muted,
  }) async {
    try {
      final result = await _client.rpc(
        'set_conversation_notifications_muted',
        params: {
          'p_conversation_id': conversationId,
          'p_muted': muted,
        },
      );
      return result == true;
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  RealtimeChannel subscribe({
    required String userId,
    required void Function() onChange,
  }) {
    return _client
        .channel('user-notifications-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'user_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
  }
}
