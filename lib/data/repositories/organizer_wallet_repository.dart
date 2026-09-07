import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/app_exception.dart';
import '../../core/utils/error_mapper.dart';
import '../../domain/models/organizer_wallet.dart';

class OrganizerWalletRepository {
  OrganizerWalletRepository(this._client);

  final SupabaseClient _client;

  Future<OrganizerWallet?> fetchMyWallet() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return null;

      final row = await _client
          .from('organizer_wallets')
          .select()
          .eq('organizer_id', uid)
          .maybeSingle()
          .timeout(const Duration(seconds: 12));

      if (row == null) return null;
      return OrganizerWallet.fromJson(Map<String, dynamic>.from(row));
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<List<OrganizerTransaction>> fetchMyTransactions({
    int limit = 50,
  }) async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return const [];

      final rows = await _client
          .from('organizer_transactions')
          .select(
            'id, organizer_id, event_id, participant_id, amount, type, '
            'description, created_at, event:events(title)',
          )
          .eq('organizer_id', uid)
          .order('created_at', ascending: false)
          .limit(limit)
          .timeout(const Duration(seconds: 15));

      final list = <OrganizerTransaction>[];
      for (final raw in rows as List) {
        final map = Map<String, dynamic>.from(raw as Map);
        // Enrich nickname from description "Подтверждение: Nick · Event"
        final desc = map['description'] as String? ?? '';
        final nick = _nicknameFromDescription(desc);
        if (nick != null) map['participant_nickname'] = nick;
        list.add(OrganizerTransaction.fromJson(map));
      }
      return list;
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<OrganizerDashboardStats> fetchDashboardStats() async {
    try {
      final row = await _client
          .rpc('organizer_dashboard_stats')
          .timeout(const Duration(seconds: 12));
      return OrganizerDashboardStats.fromJson(
        Map<String, dynamic>.from(row as Map),
      );
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<num> fetchAttendanceRewardSetting() async {
    try {
      final row = await _client
          .from('app_settings')
          .select('value')
          .eq('key', 'organizer_attendance_reward')
          .maybeSingle();
      return num.tryParse('${row?['value']}') ?? 100;
    } catch (_) {
      return 100;
    }
  }

  String? _nicknameFromDescription(String desc) {
    // "Подтверждение: Voron · Стальной щит"
    final prefix = 'Подтверждение: ';
    if (!desc.startsWith(prefix)) return null;
    final rest = desc.substring(prefix.length);
    final sep = rest.indexOf(' · ');
    if (sep <= 0) return rest.trim().isEmpty ? null : rest.trim();
    return rest.substring(0, sep).trim();
  }

  RealtimeChannel subscribeWallet({
    required String organizerId,
    required void Function() onChange,
  }) {
    final channel = _client.channel('wallet-$organizerId');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'organizer_wallets',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'organizer_id',
            value: organizerId,
          ),
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'organizer_transactions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'organizer_id',
            value: organizerId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
    return channel;
  }
}
