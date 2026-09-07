class RankingPlayerEntry {
  const RankingPlayerEntry({
    required this.id,
    required this.nickname,
    required this.city,
    required this.rating,
    required this.rank,
    this.avatarUrl,
  });

  final String id;
  final String nickname;
  final String city;
  final int rating;
  final int rank;
  final String? avatarUrl;

  factory RankingPlayerEntry.fromJson(Map<String, dynamic> json) {
    return RankingPlayerEntry(
      id: json['id'] as String,
      nickname: (json['nickname'] as String?) ?? 'Боец',
      city: (json['city'] as String?) ?? '',
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}

class RankingClanEntry {
  const RankingClanEntry({
    required this.id,
    required this.name,
    required this.tag,
    required this.rating,
    required this.membersCount,
    required this.rank,
    this.avatarUrl,
  });

  final String id;
  final String name;
  final String tag;
  final int rating;
  final int membersCount;
  final int rank;
  final String? avatarUrl;

  String get displayTag => '[${tag.toUpperCase()}]';

  factory RankingClanEntry.fromJson(Map<String, dynamic> json) {
    return RankingClanEntry(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? 'Клан',
      tag: (json['tag'] as String?) ?? 'CLAN',
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      membersCount: (json['members_count'] as num?)?.toInt() ?? 0,
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}

enum RankingEntityTab { players, clans }

enum RankingScopeTab { regional, global }
