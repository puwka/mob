# Деплой админки на Vercel

Админка — Next.js 15 в папке `admin/`. Отдельный бэкенд не нужен: используется тот же Supabase, что и у мобильного приложения.

## Что уже готово

- `vercel.json` — framework Next.js
- `next.config.ts` — production-настройки
- `.env.example` — список переменных
- `npm run build` проходит локально

## Переменные окружения (Vercel)

В **Project → Settings → Environment Variables** добавьте для Production (и Preview при желании):

| Name | Value |
|------|--------|
| `NEXT_PUBLIC_SUPABASE_URL` | `https://xxxx.supabase.co` |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | anon public key из Supabase → Settings → API |

Значения те же, что в `admin/.env.local`.

## Вариант A — через GitHub (рекомендуется)

1. Создайте репозиторий на GitHub и запушьте проект (корень `d:\proj` или только `admin`).
2. [vercel.com/new](https://vercel.com/new) → Import репозитория.
3. Настройки проекта:
   - **Framework Preset:** Next.js
   - **Root Directory:** `admin` (если в репо весь `proj`)  
     или `.` (если в репо только содержимое `admin`)
   - **Build Command:** `npm run build`
   - **Install Command:** `npm install`
4. Добавьте env-переменные выше → Deploy.

## Вариант B — через CLI без Git

```bash
cd admin
npx vercel login
npx vercel          # preview
npx vercel --prod   # production
```

При первом запуске CLI спросит:
- Set up and deploy? → Y
- Which scope? → ваш аккаунт/команда
- Link to existing project? → N (первый раз)
- Project name → например `strikeball-admin`
- In which directory is your code? → `./`
- Затем добавьте env в дашборде Vercel и сделайте `npx vercel --prod` ещё раз.

## Supabase Auth (обязательно после первого деплоя)

В Supabase → **Authentication → URL Configuration**:

1. **Site URL** — ваш production URL, например `https://strikeball-admin.vercel.app`
2. **Redirect URLs** — добавьте:
   - `https://strikeball-admin.vercel.app/**`
   - `https://*.vercel.app/**` (для preview-деплоев)

Без этого сессии/редиректы на проде могут ломаться.

## Проверка после деплоя

1. Откройте `https://<project>.vercel.app/login`
2. Войдите телефоном + паролем админа из `admin_users`
3. Должен открыться `/dashboard`

Если «Аккаунт не состоит в admin_users» — пользователь есть в Auth, но нет строки в `public.admin_users`.

## Важно

- **Не** кладите `SUPABASE_SERVICE_ROLE_KEY` в клиентский Next — админка работает через anon key + RLS / RPC под ролью админа.
- `.env.local` в git не коммитится (см. `.gitignore`).
- Root Directory на Vercel должен указывать на папку с `package.json` админки.
