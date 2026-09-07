# Tactical — Flutter + Supabase

Мобильное приложение (Android / iOS) для тактических мероприятий:  
авторизация, профиль с XP/уровнями/достижениями, мероприятия и запись на них.

Стек: **Flutter · Dart · Material 3 · Riverpod · GoRouter · supabase_flutter**

---

## 1. Структура проекта

```
lib/
  main.dart
  core/           # theme, router, config, validators, constants
  data/           # repositories (Supabase access)
  domain/         # models
  services/       # XP, Level, Achievements, Progression, Avatar Storage
  presentation/
    providers/    # Riverpod
    screens/      # auth, profile, events, main
  widgets/        # shared UI
supabase/
  migrations/     # SQL schema, RLS, seeds
.env.example
```

Слойность: **UI → Provider → Service → Repository → Supabase**  
Прямых вызовов Supabase из UI нет.

---

## 2. Реализованные функции

- Регистрация / вход по телефону + паролю (Supabase Auth)
- Сессия сохраняется и восстанавливается после перезапуска
- Профиль: avatar, nickname, city, bio, stats, XP, level
- Редактирование профиля + загрузка/удаление аватара (Storage)
- XP / уровни (`XpService` + `LevelService`)
- Достижения + прогресс + экран «Все достижения»
- Мероприятия: фильтр по городу, детали, запись / отмена
- После записи: пересчёт XP, уровня, достижений без перезапуска
- Realtime обновление участников
- Dark tactical UI (graphite + lime)

---

## 3. Таблицы Supabase

| Таблица | Назначение |
|--------|------------|
| `profiles` | Профиль пользователя |
| `achievements` | Каталог достижений |
| `user_achievements` | Прогресс пользователя |
| `events` | Мероприятия |
| `event_participants` | Записи на мероприятия (UNIQUE event+user) |

Auth: `auth.users` (управляется Supabase Auth)

---

## 4. SQL migrations / seeds

Выполнять **по порядку** в SQL Editor:

1. `20260322000000_create_profiles.sql`
2. `20260322000001_create_achievements.sql`
3. `20260322000002_create_avatars_bucket.sql`
4. `20260322000003_create_events.sql`
5. `20260322000004_seed_events.sql` *(после хотя бы 1 профиля)*
6. `20260322000005_event_progression.sql`
7. `20260322000006_rls_hardening.sql`
8. `20260322000007_create_marketplace.sql`
9. `20260322000008_listing_images_bucket.sql`
10. `20260322000009_seed_categories.sql`
11. `20260322000010_seed_listings.sql`
12. `20260322000011_create_messaging.sql`
13. `20260322000012_seed_clan_chat.sql`
14. `20260322000013_fix_messaging_rls.sql`
15. `20260322000014_clans_full.sql`
16. `20260322000015_ranking.sql`
17. `20260322000016_integration_hardening.sql`
18. `20260322000017_fix_no_auto_clan.sql`
19. `20260322000018_app_roles_and_qr.sql`
20. `20260322000019_events_attendance.sql`
21. `20260322000020_organizer_economy.sql`
22. `20260322000021_profile_photos.sql`
23. `20260322000022_admin_panel.sql` — web-админка (`admin/`)
24. `20260322000023_admin_phone_login.sql` — вход админа по телефону
25. `20260322000024_admin_content_part1.sql` — events/participants RPC + storage
26. `20260322000025_admin_content_part2.sql` — clans/market/achievements/cities
27. `20260322000026_admin_final_part1.sql` — dialogs, RBAC, settings seeds
28. `20260322000027_admin_final_part2.sql` — economy, attendance, search, notifications



Награда за QR (можно менять без релиза):

```sql
UPDATE public.app_settings
SET value = '100'
WHERE key = 'organizer_attendance_reward';
```



Назначение организатора (SQL Editor / service role):

```sql
SELECT public.admin_set_app_role('<user_uuid>', 'organizer');
```


RPC: `join_event`, `get_user_events_count`, `is_nickname_available`, `sync_user_achievements`, `increment_listing_views`, `open_market_chat`, `open_user_chat`, `open_clan_chat`, `send_chat_message`, `mark_conversation_read`

---

## 5. Storage buckets

| Bucket | Public | Назначение |
|--------|--------|------------|
| `avatars` | да (read) | Аватары `{user_id}/avatar.*` |
| `listing-images` | да (read) | Фото объявлений `{user_id}/{listing_id}/*` |

Политики: upload/update/delete только в своей папке.

---

## 6. Переменные окружения

Файл `.env` (из `.env.example`):

```env
SUPABASE_URL=https://YOUR_PROJECT.supabase.co
SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY
```

---

## 7. Запуск

### Supabase Dashboard

1. Создайте проект, скопируйте URL и anon key в `.env`
2. **Authentication → Providers → Email**: включить, **Confirm email = OFF**
3. Выполните все SQL-миграции по порядку
4. **Database → Replication**: таблица `event_participants` в Realtime

### Приложение

```bash
flutter pub get
flutter run
```

Телефон + пароль → Auth identity вида `79001234567@phone.local`  
Пароль хранит только Supabase Auth.

---

## 8. Демо-сценарий для заказчика

1. Открыть приложение  
2. Регистрация: телефон, ник, город, пароль  
3. Профиль → уровень / XP / достижения  
4. «Все достижения»  
5. Вкладка **Игры** → фильтр города → карточка мероприятия  
6. **Участвовать** → статус «Вы участвуете»  
7. В Supabase Table Editor: строка в `event_participants`  
8. Повторно записаться нельзя (кнопка участия недоступна / UNIQUE)  
9. Вернуться в профиль → XP / уровень / ачивки обновлены  
10. Закрыть приложение → открыть снова → сессия на месте  

---

## Проверки качества

```bash
flutter analyze
flutter test
```
