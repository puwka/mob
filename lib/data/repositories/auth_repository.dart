import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/app_exception.dart';
import '../../core/utils/error_mapper.dart';
import '../../core/utils/phone_utils.dart';
import '../../domain/models/profile.dart';
import 'profile_repository.dart';

class AuthRepository {
  AuthRepository({
    required SupabaseClient client,
    required ProfileRepository profileRepository,
  })  : _client = client,
        _profiles = profileRepository;

  final SupabaseClient _client;
  final ProfileRepository _profiles;

  Session? get currentSession => _client.auth.currentSession;
  User? get currentUser => _client.auth.currentUser;
  bool get isAuthenticated => currentSession != null;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<Profile> register({
    required String phone,
    required String nickname,
    required String city,
    required String password,
  }) async {
    final e164 = PhoneUtils.toE164(phone);
    final email = PhoneUtils.toAuthEmail(phone);
    final nick = nickname.trim();

    try {
      final available = await _profiles.isNicknameAvailable(nick);
      if (!available) {
        throw const AppException('Этот никнейм уже занят');
      }

      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {
          'phone': e164,
          'nickname': nick,
          'city': city,
        },
      );

      final user = response.user;
      if (user == null) {
        throw const AppException(
          'Не удалось создать аккаунт. Проверьте настройки Auth в Supabase.',
        );
      }

      // Ensure session exists (email confirmation may be disabled in project).
      if (response.session == null) {
        await _client.auth.signInWithPassword(email: email, password: password);
      }

      return _profiles.create(
        Profile(
          id: user.id,
          phone: e164,
          nickname: nick,
          city: city,
          createdAt: DateTime.now().toUtc(),
        ),
      );
    } on AppException {
      rethrow;
    } on AuthException catch (e) {
      throw AppException(ErrorMapper.map(e));
    } on PostgrestException catch (e) {
      throw AppException(ErrorMapper.map(e));
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<Profile> login({
    required String phone,
    required String password,
  }) async {
    final email = PhoneUtils.toAuthEmail(phone);

    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = response.user;
      if (user == null) {
        throw const AppException('Неверный телефон или пароль');
      }

      return _profiles.getById(user.id);
    } on AppException {
      rethrow;
    } on AuthException catch (e) {
      throw AppException(ErrorMapper.map(e));
    } on PostgrestException catch (e) {
      throw AppException(ErrorMapper.map(e));
    } catch (e) {
      throw AppException(ErrorMapper.map(e));
    }
  }

  Future<void> logout() async {
    await _client.auth.signOut();
  }
}
