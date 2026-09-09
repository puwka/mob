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

  Future<num> fetchMinWithdrawalAmount() async {
    try {
      final row = await _client
          .from('app_settings')
          .select('value')
          .eq('key', 'min_withdrawal_amount')
          .maybeSingle();
      return num.tryParse('${row?['value']}') ?? 100;
    } catch (_) {
      return 100;
    }
  }

  Future<num> fetchWithdrawalFee() async {
    try {
      final row = await _client
          .from('app_settings')
          .select('value')
          .eq('key', 'withdrawal_fee')
          .maybeSingle();
      return num.tryParse('${row?['value']}') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<List<OrganizerWithdrawalRequest>> fetchMyWithdrawals({
    int limit = 20,
  }) async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return const [];

      final rows = await _client
          .from('organizer_withdrawal_requests')
          .select()
          .eq('organizer_id', uid)
          .order('created_at', ascending: false)
          .limit(limit)
          .timeout(const Duration(seconds: 12));

      return [
        for (final raw in rows as List)
          OrganizerWithdrawalRequest.fromJson(
            Map<String, dynamic>.from(raw as Map),
          ),
      ];
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<OrganizerWithdrawalRequest> requestWithdrawal({
    required num amount,
    required String paymentDetails,
  }) async {
    try {
      final row = await _client.rpc(
        'request_organizer_withdrawal',
        params: {
          'p_amount': amount,
          'p_payment_details': paymentDetails.trim(),
        },
      );
      return OrganizerWithdrawalRequest.fromJson(
        Map<String, dynamic>.from(row as Map),
      );
    } catch (e) {
      throw AppException(_mapWithdrawalError(e));
    }
  }

  String _mapWithdrawalError(Object e) {
    final raw = e.toString().toUpperCase();
    if (raw.contains('INSUFFICIENT_BALANCE')) {
      return 'Недостаточно средств на балансе';
    }
    if (raw.contains('PENDING_EXISTS')) {
      return 'У вас уже есть заявка на проверке';
    }
    if (raw.contains('AMOUNT_TOO_LOW')) {
      return 'Сумма меньше минимальной для вывода';
    }
    if (raw.contains('INVALID_PAYMENT_DETAILS')) {
      return 'Укажите реквизиты для выплаты (минимум 5 символов)';
    }
    if (raw.contains('INVALID_AMOUNT')) {
      return 'Укажите корректную сумму';
    }
    if (raw.contains('NOT_ORGANIZER')) {
      return 'Вывод доступен только организаторам';
    }
    return ErrorMapper.map(e);
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
