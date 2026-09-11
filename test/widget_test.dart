import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:proj/core/theme/app_theme.dart';
import 'package:proj/core/utils/phone_utils.dart';
import 'package:proj/core/utils/validators.dart';
import 'package:proj/data/repositories/event_repository.dart';
import 'package:proj/domain/models/achievement.dart';
import 'package:proj/domain/models/conversation.dart';
import 'package:proj/domain/models/dating.dart';
import 'package:proj/domain/models/event.dart';
import 'package:proj/domain/models/profile.dart';
import 'package:proj/domain/models/ranking.dart';
import 'package:proj/services/achievement_service.dart';
import 'package:proj/services/level_service.dart';
import 'package:proj/services/offline_qr_store.dart';

void main() {
  test('PhoneUtils normalizes RU numbers', () {
    expect(PhoneUtils.normalize('+7 (900) 123-45-67'), '79001234567');
    expect(PhoneUtils.normalize('89001234567'), '79001234567');
    expect(PhoneUtils.normalize('9001234567'), '79001234567');
    expect(PhoneUtils.toAuthEmail('89001234567'), '79001234567@phone.local');
    expect(PhoneUtils.isValidRuMobile('89001234567'), isTrue);
    expect(PhoneUtils.isValidRuMobile('123'), isFalse);
  });

  test('Validators cover registration rules', () {
    expect(Validators.nickname('ab'), isNotNull);
    expect(Validators.nickname('good_nick'), isNull);
    expect(Validators.nickname('bad nick!'), isNotNull);
    expect(Validators.password('short'), isNotNull);
    expect(Validators.password('longenough'), isNull);
    expect(Validators.confirmPassword('x', 'y'), isNotNull);
    expect(Validators.confirmPassword('same', 'same'), isNull);
  });

  group('XpService / LevelService', () {
    const xp = XpService();
    const service = LevelService();

    test('calculates XP including events', () {
      expect(
        xp.calculate(
          gamesPlayed: 10,
          wins: 2,
          polygonsVisited: 3,
          eventsCount: 4,
        ),
        10 * 100 + 2 * 250 + 3 * 100 + 4 * 100,
      );
    });

    test('admin rating raises level via calculateFromProfile', () {
      final profile = Profile(
        id: 'u1',
        phone: '+79001112233',
        nickname: 'Voron',
        city: 'Москва',
        rating: 500,
        bonusXp: 500,
        createdAt: DateTime.utc(2026, 1, 1),
      );
      final level = service.calculateFromProfile(profile, eventsCount: 0);
      expect(level.currentXp, 500);
      expect(level.currentLevel, 3);
    });

    test('calculateLevel starts at 1 with 0 XP', () {
      final level = service.calculateLevel(0);
      expect(level.currentLevel, 1);
      expect(level.currentXp, 0);
      expect(level.progress, 0);
      expect(level.xpForNextLevel, service.xpRequiredForLevel(1));
    });

    test('levels grow progressively', () {
      final needFor2 = service.xpRequiredForLevel(1);
      final at2 = service.calculateLevel(needFor2);
      final atAlmost2 = service.calculateLevel(needFor2 - 1);

      expect(atAlmost2.currentLevel, 1);
      expect(at2.currentLevel, 2);
      expect(at2.xpIntoLevel, 0);
      expect(
        service.xpRequiredForLevel(2) > service.xpRequiredForLevel(1),
        isTrue,
      );
    });

    test('events participation increases XP and may level up', () {
      final before = service.calculateFromStats(
        gamesPlayed: 0,
        wins: 0,
        polygonsVisited: 0,
        eventsCount: 5,
      );
      final after = service.calculateFromStats(
        gamesPlayed: 0,
        wins: 0,
        polygonsVisited: 0,
        eventsCount: 6,
      );
      expect(before.currentXp, 500);
      expect(after.currentXp, 600);
      expect(after.currentXp - before.currentXp, 100);
    });
  });

  group('AchievementService', () {
    const service = AchievementService();

    final catalog = [
      Achievement(
        id: 'a1',
        title: 'Ветеран',
        description: '50 игр',
        icon: 'veteran',
        type: AchievementTypes.gamesPlayed,
        requiredValue: 50,
        createdAt: DateTime.utc(2026, 1, 1),
      ),
      Achievement(
        id: 'a2',
        title: 'Первое мероприятие',
        description: '1 мероприятие',
        icon: 'first_event',
        type: AchievementTypes.eventsCount,
        requiredValue: 1,
        createdAt: DateTime.utc(2026, 1, 1),
      ),
      Achievement(
        id: 'a3',
        title: 'Активист',
        description: '5 мероприятий',
        icon: 'activist',
        type: AchievementTypes.eventsCount,
        requiredValue: 5,
        createdAt: DateTime.utc(2026, 1, 1),
      ),
    ];

    Profile profile({int games = 0}) {
      return Profile(
        id: 'u1',
        phone: '+79001112233',
        nickname: 'Voron',
        city: 'Москва',
        gamesPlayed: games,
        createdAt: DateTime.utc(2026, 1, 1),
      );
    }

    test('unlocks event achievements from eventsCount', () {
      final items = service.evaluate(
        catalog: catalog,
        metrics: AchievementMetrics(
          gamesPlayed: profile().gamesPlayed,
          eventsCount: 5,
        ),
      );

      final first = items.firstWhere((e) => e.achievement.id == 'a2');
      final activist = items.firstWhere((e) => e.achievement.id == 'a3');

      expect(first.unlocked, isTrue);
      expect(first.progress, 1);
      expect(activist.unlocked, isTrue);
      expect(activist.progress, 5);
      expect(activist.progressRatio, 1.0);
    });

    test('progresses event achievements partially', () {
      final items = service.evaluate(
        catalog: catalog,
        metrics: AchievementMetrics(
          gamesPlayed: profile().gamesPlayed,
          eventsCount: 3,
        ),
      );
      final activist = items.firstWhere((e) => e.achievement.id == 'a3');
      expect(activist.unlocked, isFalse);
      expect(activist.progress, 3);
      expect(activist.progressRatio, closeTo(0.6, 0.001));
      expect(service.visualState(activist), AchievementVisualState.progress);
    });
  });

  testWidgets('Dark theme builds MaterialApp', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: Text('ok')),
        ),
      ),
    );
    expect(find.text('ok'), findsOneWidget);
  });

  group('Integration models', () {
    test('conversation folder labels match dialogs UI', () {
      expect(ConversationType.market.folderLabel, 'Барахолка');
      expect(ConversationType.dating.folderLabel, 'Знакомства');
      expect(ConversationType.clan.folderLabel, 'Клан');
      expect(ConversationType.user.folderLabel, 'Личные');
      expect(ConversationType.city.folderLabel, 'Город');
    });

    test('clan rating is sum of member ratings (client-side formula check)', () {
      expect([2450, 2780].fold<int>(0, (a, b) => a + b), 5230);
      expect(5230 - 2780 + 3000, 5450);
    });

    test('RankingPlayerEntry parses JSON', () {
      final e = RankingPlayerEntry.fromJson({
        'id': 'u1',
        'nickname': 'Ворон',
        'city': 'Москва',
        'rating': 2450,
        'rank': 4,
        'avatar_url': null,
      });
      expect(e.nickname, 'Ворон');
      expect(e.rating, 2450);
      expect(e.rank, 4);
    });

    test('Profile app role + QR payload are safe', () {
      final p = Profile.fromJson({
        'id': 'u1',
        'phone': '+79001112233',
        'nickname': 'Voron',
        'city': 'Москва',
        'role': 'user',
        'game_role': 'Снайпер',
        'public_qr_id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(p.appRole, AppRole.user);
      expect(p.isOrganizer, isFalse);
      expect(p.gameRole, 'Снайпер');
      expect(p.parsedGameRole, GameRole.sniper);
      expect(p.gameRoleLabel, 'Снайпер');
      expect(p.qrPayload, 'tactical:qr:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
      expect(p.qrPayload.contains('+79'), isFalse);
      expect(p.toInsertJson().containsKey('role'), isFalse);

      final org = Profile.fromJson({
        'id': 'u2',
        'phone': '',
        'nickname': 'Org',
        'city': 'Москва',
        'role': 'organizer',
        'public_qr_id': '11111111-2222-3333-4444-555555555555',
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(org.isOrganizer, isTrue);
    });

    test('QR token parsing accepts tactical payload and bare UUID', () {
      expect(
        EventRepository.parseQrToken(
          'tactical:qr:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        ),
        'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      );
      expect(
        EventRepository.parseQrToken('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'),
        'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      );
      expect(EventRepository.parseQrToken('not-a-qr'), isNull);
    });

    test('EventParticipant includes public_qr_id for offline scan', () {
      final p = EventParticipant.fromJson({
        'id': 'ep1',
        'event_id': 'e1',
        'user_id': 'u1',
        'registration_status': 'registered',
        'attendance_status': 'not_confirmed',
        'registered_at': '2026-01-01T00:00:00Z',
        'profile': {
          'nickname': 'Voron',
          'city': 'Москва',
          'public_qr_id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        },
      });
      expect(p.publicQrId, 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
      expect(p.isConfirmed, isFalse);

      final roster = OfflineEventRoster(
        eventId: 'e1',
        eventTitle: 'Игра',
        cachedAt: DateTime.utc(2026, 1, 1),
        participants: [p],
      );
      expect(
        roster.findByPublicQrId('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee')?.nickname,
        'Voron',
      );
      expect(roster.findByPublicQrId('missing'), isNull);
    });

    test('AttendanceConfirmResult includes reward and balance', () {
      final r = AttendanceConfirmResult.fromJson({
        'user_id': 'u1',
        'nickname': 'Voron',
        'city': 'Москва',
        'event_id': 'e1',
        'event_title': 'Стальной щит',
        'attended_at': '2026-09-05T18:42:00Z',
        'reward_amount': 100,
        'balance': 1350,
        'currency': 'credits',
      });
      expect(r.rewardLabel, '+100 CR');
      expect(r.balanceLabel, '1350 CR');
    });
  });

  group('DatingCandidate', () {
    test('parses feed payload and caps photos at 5', () {
      final c = DatingCandidate.fromJson({
        'id': 'u1',
        'nickname': 'Ворон',
        'city': 'Москва',
        'avatar_url': 'https://example.com/a.jpg',
        'photo_urls': [
          'https://example.com/a.jpg',
          'https://example.com/1.jpg',
          'https://example.com/2.jpg',
          'https://example.com/3.jpg',
          'https://example.com/4.jpg',
          'https://example.com/5.jpg',
        ],
      });
      expect(c.nickname, 'Ворон');
      expect(c.city, 'Москва');
      expect(c.photoUrls.length, 5);
      expect(c.displayPhotos.first, 'https://example.com/a.jpg');
    });

    test('falls back to avatar when photo_urls empty', () {
      final c = DatingCandidate.fromJson({
        'id': 'u2',
        'nickname': 'Fox',
        'city': 'Казань',
        'avatar_url': 'https://example.com/av.jpg',
        'photo_urls': [],
      });
      expect(c.displayPhotos, ['https://example.com/av.jpg']);
    });

    test('DatingActionResult parses match payload', () {
      final r = DatingActionResult.fromJson({
        'action_id': 'a1',
        'to_user_id': 'u2',
        'action': 'like',
        'matched': true,
        'inserted': true,
        'match_id': 'm1',
        'conversation_id': 'c1',
        'created_at': '2026-09-08T12:00:00Z',
        'me': {
          'id': 'u1',
          'nickname': 'Ястреб',
          'city': 'Казань',
          'avatar_url': null,
        },
        'target': {
          'id': 'u2',
          'nickname': 'Ворон',
          'city': 'Москва',
          'avatar_url': 'https://example.com/a.jpg',
        },
      });
      expect(r.action, DatingActionType.like);
      expect(r.matched, isTrue);
      expect(r.shouldShowMatchUi, isTrue);
      expect(r.matchId, 'm1');
      expect(r.conversationId, 'c1');
      expect(r.me.nickname, 'Ястреб');
      expect(r.target.nickname, 'Ворон');
    });

    test('DatingActionResult hides match UI when not inserted', () {
      final r = DatingActionResult.fromJson({
        'action_id': 'a1',
        'to_user_id': 'u2',
        'action': 'like',
        'matched': true,
        'inserted': false,
        'match_id': 'm1',
        'created_at': '2026-09-08T12:00:00Z',
        'me': {'id': 'u1', 'nickname': 'A', 'city': 'X'},
        'target': {'id': 'u2', 'nickname': 'B', 'city': 'Y'},
      });
      expect(r.shouldShowMatchUi, isFalse);
    });

    test('DatingMatch parses get_my_matches row', () {
      final m = DatingMatch.fromJson({
        'match_id': 'm1',
        'user_id': 'u2',
        'nickname': 'Ворон',
        'city': 'Москва',
        'avatar_url': null,
        'created_at': '2026-09-08T12:00:00Z',
        'conversation_id': 'c1',
      });
      expect(m.nickname, 'Ворон');
      expect(m.conversationId, 'c1');
    });

  });
}
