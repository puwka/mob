# Admin Panel — Final Report

## 1. Структура

```
admin/
  src/
    app/
      login/
      (admin)/
        dashboard/
        users/[id]/
        organizers/
        events/[id]/
        attendance/
        clans/
        ranking/
        market/ + moderation/
        chats/
        achievements/
        dictionaries/
        economy/
        notifications/
        settings/
        logs/
    components/layout|ui/
    hooks/use-permissions.ts
    lib/api/ admin.ts | content.ts | final.ts
    providers/
supabase/migrations/
  20260322000022…027_admin_*.sql
```

## 2. Страницы

| Route | Назначение |
|-------|------------|
| `/login` | Вход по телефону |
| `/dashboard` | Сводка |
| `/users`, `/users/[id]` | Пользователи |
| `/organizers` | Организаторы |
| `/events`, `/events/[id]` | Мероприятия + участники |
| `/attendance` | Посещаемость / QR confirm |
| `/clans` | Кланы |
| `/ranking` | Рейтинг |
| `/market`, `/market/moderation` | Барахолка |
| `/chats` | Диалоги |
| `/achievements` | Достижения |
| `/dictionaries` | Справочники |
| `/economy` | Экономика + транзакции |
| `/notifications` | Уведомления (очередь) |
| `/settings` | app_settings |
| `/logs` | Audit logs |

## 3. Таблицы Supabase (ключевые)

profiles, events, event_participants, clans, clan_members, clan_join_requests,  
listings, listing_images, listing_favorites, categories,  
conversations, conversation_members, messages,  
achievements, user_achievements, profile_photos,  
organizer_wallets, organizer_transactions, app_settings,  
admin_users, admin_audit_logs, admin_notifications, app_cities

## 4. Migrations (admin)

- `000022` admin_users, audit, profile status, core admin RPCs  
- `000023` phone login column  
- `000024–025` content management  
- `000026–027` final: dialogs, RBAC, economy, attendance, settings, search, notifications  

## 5. RPC (финал)

`admin_has_perm`, `admin_my_permissions`, `require_perm`  
`admin_list_conversations`, `admin_list_messages`, `admin_soft_delete_message`,  
`admin_set_conversation_status`, `admin_delete_conversation`  
`admin_economy_stats`, `admin_economy_organizers`, `admin_list_transactions`  
`admin_adjust_organizer_balance` (**super_admin only**)  
`admin_list_settings`, `admin_upsert_setting` (**super_admin**), `get_app_setting`  
`admin_list_attendance`, `admin_confirm_participant`  
`admin_list_notifications`, `admin_create_notification`  
`admin_global_search`

## 6. RLS

Админы читают conversations/members/messages при `admin_has_perm('dialogs')`.  
Экономика / settings — через SECURITY DEFINER RPC (клиент не UPDATE balance напрямую).

## 7. Storage buckets

`avatars`, `listing-images`, `event-images`, `clan-images`, `achievement-icons`

## 8–9. Роли и права

| | super_admin | admin | moderator |
|--|:--:|:--:|:--:|
| Dashboard / search / logs | ✓ | ✓ | ✓ |
| Users / organizers / events / clans / ranking | ✓ | ✓ | |
| Market / moderation / dialogs | ✓ | ✓ | ✓ |
| Economy view / attendance / settings view | ✓ | ✓ | |
| Economy adjust / settings write | ✓ | | |
| Notifications / achievements / dictionaries | ✓ | ✓ | |

Права проверяются в PostgreSQL (`admin_has_perm` / `require_perm`), UI только скрывает пункты меню.

## 10. Запуск

```bash
cd admin
cp .env.example .env.local   # NEXT_PUBLIC_SUPABASE_URL / ANON_KEY
npm install
npm run dev
```

Применить SQL `000022`…`000027` в порядке.

Первый админ:

```sql
-- Auth user email: 79001234567@phone.local
INSERT INTO public.admin_users (id, phone, role)
VALUES ('<uuid>', '+79001234567', 'super_admin');
```

## 11. Env

```
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
```

## 12. Сценарии для ручной проверки

1. LOGIN → DASHBOARD → USER → ORGANIZER → EVENT → PARTICIPANT → ATTENDANCE confirm → REWARD → ECONOMY/TX → LOGS  
2. USER → LISTING → CHAT (soft-delete message)  
3. CLAN → MEMBERS → rating auto-sum  
4. PLAYER rating change → clan rating update  
5. Settings: change `organizer_attendance_reward` без релиза приложения  
6. Moderator: только market/dialogs/moderation; Super Admin: balance adjust  

## Hardcoded cleanup

- Rewards / photo limits → `app_settings` + `get_app_setting`  
- Achievements catalog → DB (`is_active`)  
- Cities → `app_cities`  
- Permissions → backend RPC, not client-only  
