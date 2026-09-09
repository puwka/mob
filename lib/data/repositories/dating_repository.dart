import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/app_exception.dart';
import '../../core/utils/error_mapper.dart';
import '../../domain/models/dating.dart';

class DatingRepository {
  DatingRepository(this._client);

  final SupabaseClient _client;

  Future<List<DatingCandidate>> fetchCandidates({
    int limit = 20,
    String? city,
  }) async {
    try {
      final raw = await _client
          .rpc(
            'dating_fetch_candidates',
            params: {
              'p_limit': limit,
              'p_city': city,
            },
          )
          .timeout(const Duration(seconds: 15));

      return [
        for (final item in _asList(raw))
          DatingCandidate.fromJson(Map<String, dynamic>.from(item as Map)),
      ];
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<DatingActionResult> processAction({
    required String targetUserId,
    required DatingActionType action,
  }) async {
    try {
      final raw = await _client
          .rpc(
            'process_dating_action',
            params: {
              'p_target_user_id': targetUserId,
              'p_action': action.dbValue,
            },
          )
          .timeout(const Duration(seconds: 12));

      return DatingActionResult.fromJson(_asMap(raw));
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  /// Backward-compatible alias.
  Future<DatingActionResult> recordAction({
    required String toUserId,
    required DatingActionType action,
  }) {
    return processAction(targetUserId: toUserId, action: action);
  }

  Future<void> blockUser(String blockedUserId) async {
    try {
      await _client
          .rpc('block_user', params: {'p_blocked_user_id': blockedUserId})
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<String> reportUser({
    required String targetUserId,
    required String reason,
    String? description,
  }) async {
    try {
      final id = await _client
          .rpc(
            'report_user',
            params: {
              'p_target_user_id': targetUserId,
              'p_reason': reason,
              'p_description': description,
            },
          )
          .timeout(const Duration(seconds: 12));
      return id as String;
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<List<DatingMatch>> fetchMyMatches() async {
    try {
      final raw = await _client
          .rpc('get_my_matches')
          .timeout(const Duration(seconds: 12));

      return [
        for (final item in _asList(raw))
          DatingMatch.fromJson(Map<String, dynamic>.from(item as Map)),
      ];
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<List<DatingNotification>> fetchPendingNotifications() async {
    try {
      final raw = await _client
          .rpc('get_pending_dating_notifications')
          .timeout(const Duration(seconds: 12));

      return [
        for (final item in _asList(raw))
          DatingNotification.fromJson(Map<String, dynamic>.from(item as Map)),
      ];
    } catch (_) {
      // Fallback for DBs that only have the match-only RPC.
      try {
        final raw = await _client
            .rpc('get_pending_dating_match_notifications')
            .timeout(const Duration(seconds: 12));
        return [
          for (final item in _asList(raw))
            DatingNotification.fromJson({
              ...Map<String, dynamic>.from(item as Map),
              'kind': 'match',
            }),
        ];
      } catch (e) {
        throw AppException(ErrorMapper.map(e));
      }
    }
  }

  /// Backward-compatible alias.
  Future<List<DatingNotification>> fetchPendingMatchNotifications() {
    return fetchPendingNotifications();
  }

  Future<void> markNotificationSeen(String notificationId) async {
    try {
      await _client
          .rpc(
            'mark_dating_notification_seen',
            params: {'p_notification_id': notificationId},
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      await _client
          .rpc(
            'mark_dating_match_notification_seen',
            params: {'p_notification_id': notificationId},
          )
          .timeout(const Duration(seconds: 8));
    }
  }

  Future<void> markMatchNotificationSeen(String notificationId) {
    return markNotificationSeen(notificationId);
  }

  static List<dynamic> _asList(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) return raw;
    if (raw is String) {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded;
    }
    return const [];
  }

  static Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    throw AppException('Некорректный ответ сервера');
  }
}
