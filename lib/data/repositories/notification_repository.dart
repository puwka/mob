import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/app_exception.dart';
import '../../core/utils/error_mapper.dart';

class NotificationRepository {
  NotificationRepository(this._client);

  final SupabaseClient _client;

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
}
