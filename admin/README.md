# Admin Panel — Мой Страйкбол

Web-админка для мобильного приложения. Работает с **той же** Supabase, без отдельной БД.

## Стек

Next.js 15 · TypeScript · Tailwind · Supabase Auth · TanStack Query · Zod · React Hook Form

## Запуск

```bash
cd admin
cp .env.example .env.local
# заполните NEXT_PUBLIC_SUPABASE_URL и NEXT_PUBLIC_SUPABASE_ANON_KEY
npm install
npm run dev
```

Откройте http://localhost:3000

## Деплой на Vercel

Пошаговая инструкция: [`DEPLOY_VERCEL.md`](./DEPLOY_VERCEL.md)

Кратко:

1. Импортируйте репозиторий в Vercel (Root Directory = `admin`, если репо — весь проект).
2. Env: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`.
3. В Supabase Auth добавьте Site URL / Redirect URLs на `https://*.vercel.app`.

Или из папки `admin`: `npx vercel --prod`

## Миграции

Выполните в SQL Editor (по порядку, если ещё не применяли):

1. `supabase/migrations/20260322000022_admin_panel.sql`
2. `supabase/migrations/20260322000023_admin_phone_login.sql`

## Как создать первого админа

Вход как в приложении: телефон + пароль → Auth email `{digits}@phone.local`.

1. Auth → Users → Add user  
   - Email: `79001234567@phone.local`  
   - Password: ваш пароль  
2. SQL:

```sql
INSERT INTO public.admin_users (id, phone, role)
VALUES ('<auth-user-uuid>', '+79001234567', 'super_admin');
```

Либо используйте уже существующий аккаунт из приложения (тот же телефон/пароль) и добавьте его `id` в `admin_users`.

Роль `organizer` в `profiles` — **не** даёт доступ в админку.

## Stage 2 — контент

После миграций `000024` + `000025` работают разделы:

- Мероприятия + участники (confirm с начислением организатору)
- Кланы (рейтинг только как SUM, без ручного ввода)
- Рейтинг игроков/кланов
- Барахолка + модерация + категории
- Достижения (`is_active`)
- Справочники (города / категории / статусы)
- Storage: `event-images`, `clan-images`, `achievement-icons`
