import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/repositories/organizer_wallet_repository.dart';
import '../../domain/models/organizer_wallet.dart';
import 'auth_providers.dart';

final organizerWalletRepositoryProvider =
    Provider<OrganizerWalletRepository>((ref) {
  return OrganizerWalletRepository(ref.watch(supabaseClientProvider));
});

final organizerWalletProvider =
    AsyncNotifierProvider<OrganizerWalletNotifier, OrganizerWallet?>(
  OrganizerWalletNotifier.new,
);

class OrganizerWalletNotifier extends AsyncNotifier<OrganizerWallet?> {
  RealtimeChannel? _channel;

  @override
  Future<OrganizerWallet?> build() async {
    final isOrg =
        ref.watch(currentProfileProvider).valueOrNull?.isOrganizer ?? false;
    if (!isOrg) return null;

    final uid = ref.watch(currentUserProvider)?.id;
    ref.onDispose(() {
      final ch = _channel;
      _channel = null;
      if (ch != null) {
        unawaited(ref.read(supabaseClientProvider).removeChannel(ch));
      }
    });

    final wallet =
        await ref.read(organizerWalletRepositoryProvider).fetchMyWallet();

    if (uid != null) {
      _channel ??=
          ref.read(organizerWalletRepositoryProvider).subscribeWallet(
                organizerId: uid,
                onChange: () {
                  refresh(silent: true);
                  ref.invalidate(organizerTransactionsProvider);
                  ref.invalidate(organizerDashboardProvider);
                },
              );
    }

    return wallet;
  }

  Future<void> refresh({bool silent = false}) async {
    if (!silent) state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(organizerWalletRepositoryProvider).fetchMyWallet(),
    );
  }
}

final organizerTransactionsProvider =
    AsyncNotifierProvider<OrganizerTransactionsNotifier,
        List<OrganizerTransaction>>(
  OrganizerTransactionsNotifier.new,
);

class OrganizerTransactionsNotifier
    extends AsyncNotifier<List<OrganizerTransaction>> {
  @override
  Future<List<OrganizerTransaction>> build() {
    final isOrg =
        ref.watch(currentProfileProvider).valueOrNull?.isOrganizer ?? false;
    if (!isOrg) return Future.value(const []);
    return ref.read(organizerWalletRepositoryProvider).fetchMyTransactions();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(organizerWalletRepositoryProvider).fetchMyTransactions(),
    );
  }
}

final organizerDashboardProvider =
    AsyncNotifierProvider<OrganizerDashboardNotifier, OrganizerDashboardStats>(
  OrganizerDashboardNotifier.new,
);

class OrganizerDashboardNotifier
    extends AsyncNotifier<OrganizerDashboardStats> {
  @override
  Future<OrganizerDashboardStats> build() {
    final isOrg =
        ref.watch(currentProfileProvider).valueOrNull?.isOrganizer ?? false;
    if (!isOrg) {
      return Future.value(
        const OrganizerDashboardStats(
          eventsCount: 0,
          participantsCount: 0,
          confirmedToday: 0,
          balance: 0,
        ),
      );
    }
    return ref.read(organizerWalletRepositoryProvider).fetchDashboardStats();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(organizerWalletRepositoryProvider).fetchDashboardStats(),
    );
  }
}

final organizerWithdrawalsProvider = AsyncNotifierProvider<
    OrganizerWithdrawalsNotifier, List<OrganizerWithdrawalRequest>>(
  OrganizerWithdrawalsNotifier.new,
);

class OrganizerWithdrawalsNotifier
    extends AsyncNotifier<List<OrganizerWithdrawalRequest>> {
  @override
  Future<List<OrganizerWithdrawalRequest>> build() {
    final isOrg =
        ref.watch(currentProfileProvider).valueOrNull?.isOrganizer ?? false;
    if (!isOrg) return Future.value(const []);
    return ref.read(organizerWalletRepositoryProvider).fetchMyWithdrawals();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(organizerWalletRepositoryProvider).fetchMyWithdrawals(),
    );
  }

  Future<OrganizerWithdrawalRequest> request({
    required num amount,
    required String paymentDetails,
  }) async {
    final created =
        await ref.read(organizerWalletRepositoryProvider).requestWithdrawal(
              amount: amount,
              paymentDetails: paymentDetails,
            );
    await refresh();
    await ref.read(organizerWalletProvider.notifier).refresh(silent: true);
    await ref.read(organizerTransactionsProvider.notifier).refresh();
    await ref.read(organizerDashboardProvider.notifier).refresh();
    return created;
  }
}
