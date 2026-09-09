# Деплой админки на Vercel

Репозиторий — монорепо (`admin/` + Flutter). На Vercel должен собираться **только** Next.js из `admin/`.

## Правильные настройки проекта (важно)

Vercel → Project → **Settings → General**:

| Setting | Value |
|---------|--------|
| **Root Directory** | `admin` |
| **Framework Preset** | Next.js |
| **Build Command** | `npm run build` (по умолчанию) |
| **Install Command** | `npm install` (по умолчанию) |
| **Output Directory** | *пусто / Default* |

### Частая ошибка → 404

**Нельзя** одновременно:

- Root Directory = `admin`
- и Build Command = `cd admin && npm run build`

Получится путь `admin/admin` → битый деплой / **404 NOT_FOUND**.

Если Root Directory = `admin`, никакого `cd admin` в командах быть не должно.

После смены Root Directory: **Deployments → … → Redeploy**.

## Env

Settings → Environment Variables (Production):

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`

## Supabase Auth

Authentication → URL Configuration:

- Site URL: `https://ВАШ-ПРОЕКТ.vercel.app`
- Redirect URLs: `https://ВАШ-ПРОЕКТ.vercel.app/**` и `https://*.vercel.app/**`

## CLI (из папки admin, без Root Directory в UI)

```bash
cd admin
npx vercel login
npx vercel --prod
```

Здесь `cd admin` — только чтобы зайти в папку локально; в Build Command на сайте Vercel его не пишите.
