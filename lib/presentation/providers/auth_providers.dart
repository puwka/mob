import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../domain/models/profile.dart';
import '../../services/offline_qr_store.dart';
import '../../services/push_notification_service.dart';
import 'session_reset.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(supabaseClientProvider));
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    client: ref.watch(supabaseClientProvider),
    profileRepository: ref.watch(profileRepositoryProvider),
  );
});

/// Auth session stream for GoRouter redirects.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

final currentUserProvider = Provider<User?>((ref) {
  // Rebuild when auth stream emits, but always read the live client user
  // so login/register never keep a stale cached User.
  ref.watch(authStateProvider);
  return ref.watch(supabaseClientProvider).auth.currentUser;
});

final isOrganizerProvider = Provider<bool>((ref) {
  return ref.watch(currentProfileProvider).valueOrNull?.isOrganizer ?? false;
});

final currentProfileProvider =
    AsyncNotifierProvider<CurrentProfileNotifier, Profile?>(
  CurrentProfileNotifier.new,
);

class CurrentProfileNotifier extends AsyncNotifier<Profile?> {
  @override
  Future<Profile?> build() async {
    final user = ref.watch(currentUserProvider);
    if (user == null) return null;

    final repo = ref.watch(profileRepositoryProvider);
    final store = await OfflineQrStore.open();
    try {
      final profile = await repo.getByIdOrNull(user.id);
      if (profile != null) {
        await store.saveOwnProfile(profile);
      }
      return profile;
    } catch (e) {
      final cached = store.loadOwnProfile(user.id);
      if (cached != null) return cached;
      rethrow;
    }
  }

  void setProfile(Profile? profile) {
    state = AsyncData(profile);
    if (profile != null) {
      OfflineQrStore.open().then((store) => store.saveOwnProfile(profile));
    }
  }

  Future<void> refresh({bool silent = false}) async {
    if (!silent) {
      state = const AsyncLoading();
    }
    state = await AsyncValue.guard(() async {
      final user = ref.read(currentUserProvider);
      if (user == null) return null;
      final store = await OfflineQrStore.open();
      try {
        final profile =
            await ref.read(profileRepositoryProvider).getByIdOrNull(user.id);
        if (profile != null) {
          await store.saveOwnProfile(profile);
        }
        return profile;
      } catch (_) {
        final cached = store.loadOwnProfile(user.id);
        if (cached != null) return cached;
        rethrow;
      }
    });
  }
}

class AuthController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> register({
    required String phone,
    required String nickname,
    required String city,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(authRepositoryProvider).register(
            phone: phone,
            nickname: nickname,
            city: city,
            password: password,
          );
      _resetUserScopedProviders();
      await ref.read(currentProfileProvider.notifier).refresh();
    });
  }

  Future<void> login({
    required String phone,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(authRepositoryProvider).login(
            phone: phone,
            password: password,
          );
      _resetUserScopedProviders();
      await ref.read(currentProfileProvider.notifier).refresh();
    });
  }

  Future<void> logout() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final uid = ref.read(currentUserProvider)?.id;
      await PushNotificationService.instance.unregister();
      await ref.read(authRepositoryProvider).logout();
      if (uid != null) {
        final store = await OfflineQrStore.open();
        await store.clearUser(uid);
      }
      _resetUserScopedProviders();
    });
  }

  void _resetUserScopedProviders() {
    resetUserScopedProviders(ref);
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, void>(AuthController.new);
