import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/app_exception.dart';
import '../../core/utils/error_mapper.dart';
import '../../domain/models/event_rules.dart';

class EventRulesRepository {
  EventRulesRepository(this._client);

  final SupabaseClient _client;

  static const _select =
      'id, organizer_id, title, body, created_at, updated_at';

  Future<List<EventRulesTemplate>> fetchMine() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) throw const AppException('Требуется авторизация');

      final rows = await _client
          .from('event_rules')
          .select(_select)
          .eq('organizer_id', uid)
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 15));

      return [
        for (final raw in rows as List)
          EventRulesTemplate.fromJson(Map<String, dynamic>.from(raw as Map)),
      ];
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<String> create({
    required String title,
    required String body,
  }) async {
    try {
      final id = await _client.rpc(
        'create_event_rule',
        params: {
          'p_title': title,
          'p_body': body,
        },
      );
      return id as String;
    } catch (e) {
      throw AppException(_map(e));
    }
  }

  Future<void> update({
    required String id,
    required String title,
    required String body,
  }) async {
    try {
      await _client.rpc(
        'update_event_rule',
        params: {
          'p_rules_id': id,
          'p_title': title,
          'p_body': body,
        },
      );
    } catch (e) {
      throw AppException(_map(e));
    }
  }

  Future<void> delete(String id) async {
    try {
      await _client.rpc(
        'delete_event_rule',
        params: {'p_rules_id': id},
      );
    } catch (e) {
      throw AppException(_map(e));
    }
  }

  String _map(Object e) {
    final raw = e.toString().toUpperCase();
    if (raw.contains('INVALID_RULES_TITLE')) {
      return 'Укажите название шаблона (2–120 символов)';
    }
    if (raw.contains('INVALID_RULES_BODY')) {
      return 'Текст правил слишком короткий или длинный';
    }
    if (raw.contains('RULES_NOT_FOUND')) {
      return 'Шаблон правил не найден';
    }
    if (raw.contains('FORBIDDEN')) {
      return 'Недостаточно прав';
    }
    return ErrorMapper.map(e);
  }
}
