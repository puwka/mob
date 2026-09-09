import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/profile.dart';

class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  static const _table = 'profiles';

  Future<bool> isNicknameAvailable(
    String nickname, {
    String? excludingUserId,
  }) async {
    final nick = nickname.trim();

    if (excludingUserId == null) {
      final result = await _client.rpc(
        'is_nickname_available',
        params: {'p_nickname': nick},
      );
      if (result is bool) return result;
      return result == true;
    }

    final rows = await _client
        .from(_table)
        .select('id')
        .eq('nickname', nick)
        .neq('id', excludingUserId)
        .limit(1);

    return (rows as List).isEmpty;
  }

  Future<Profile> create(Profile profile) async {
    final row = await _client
        .from(_table)
        .insert(profile.toInsertJson())
        .select()
        .single();

    return _withBadge(Profile.fromJson(row));
  }

  Future<Profile> getById(String id) async {
    final row = await _client.from(_table).select().eq('id', id).single();
    return _withBadge(Profile.fromJson(row));
  }

  Future<Profile?> getByIdOrNull(String id) async {
    final rows =
        await _client.from(_table).select().eq('id', id).maybeSingle();
    if (rows == null) return null;
    return _withBadge(Profile.fromJson(rows));
  }

  Future<Profile> updateFields({
    required String id,
    String? nickname,
    String? city,
    String? avatarUrl,
    bool clearAvatarUrl = false,
    String? bio,
    bool clearBio = false,
    String? gameRole,
    bool clearGameRole = false,
    String? teamName,
  }) async {
    final payload = <String, dynamic>{};
    if (nickname != null) payload['nickname'] = nickname.trim();
    if (city != null) payload['city'] = city;
    if (clearAvatarUrl) {
      payload['avatar_url'] = null;
    } else if (avatarUrl != null) {
      payload['avatar_url'] = avatarUrl;
    }
    if (clearBio) {
      payload['bio'] = null;
    } else if (bio != null) {
      payload['bio'] = bio;
    }
    if (clearGameRole) {
      payload['game_role'] = null;
    } else if (gameRole != null) {
      payload['game_role'] = gameRole;
    }
    if (teamName != null) payload['team_name'] = teamName;

    final row = await _client
        .from(_table)
        .update(payload)
        .eq('id', id)
        .select()
        .single();

    return _withBadge(Profile.fromJson(row));
  }

  Future<Profile> update(Profile profile) async {
    return updateFields(
      id: profile.id,
      nickname: profile.nickname,
      city: profile.city,
      avatarUrl: profile.avatarUrl,
      clearAvatarUrl: profile.avatarUrl == null,
      bio: profile.bio,
      clearBio: profile.bio == null,
      gameRole: profile.gameRole,
      clearGameRole: profile.gameRole == null,
      teamName: profile.teamName,
    );
  }

  Future<Profile> _withBadge(Profile profile) async {
    try {
      final raw = await _client.rpc(
        'profile_badge_role',
        params: {'p_user_id': profile.id},
      );
      return profile.copyWith(
        badgeRole: ProfileBadgeRole.fromString(raw as String?),
      );
    } catch (_) {
      return profile.copyWith(
        badgeRole: ProfileBadgeRole.fromAppRole(profile.appRole),
      );
    }
  }

  Future<DateTime?> touchPresence() async {
    try {
      final result = await _client.rpc('touch_presence');
      if (result is String) return DateTime.parse(result);
      return DateTime.now();
    } catch (_) {
      return null;
    }
  }

  Future<DateTime?> fetchLastSeen(String userId) async {
    try {
      final row = await _client
          .from(_table)
          .select('last_seen_at')
          .eq('id', userId)
          .maybeSingle();
      final raw = row?['last_seen_at'] as String?;
      if (raw == null) return null;
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }
}
