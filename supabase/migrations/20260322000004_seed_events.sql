-- ============================================================
-- Seed: at least 6 tactical events across required cities
-- ============================================================

-- Clear previous seed by stable titles (idempotent re-run friendly)
DELETE FROM public.events
WHERE title IN (
  'Стальной щит',
  'Ночной штурм',
  'CQB Академия',
  'Лесной рейд',
  'Волжский рубеж',
  'Северный фронт',
  'Тактический спринт'
);

INSERT INTO public.events (
  title,
  description,
  city,
  location,
  event_date,
  organizer_id,
  max_participants,
  image_url
)
VALUES
(
  'Стальной щит',
  'Командное тактическое мероприятие с акцентом на оборону позиций и работу отделений. Подходит для игроков среднего уровня.',
  'Москва',
  'Полигон Северный',
  TIMESTAMPTZ '2026-09-14 18:00:00+03',
  (SELECT id FROM public.profiles ORDER BY created_at LIMIT 1),
  50,
  'https://images.unsplash.com/photo-1595590424283-b8f17842773f?w=1200&q=80'
),
(
  'Ночной штурм',
  'Ночная игра на городском полигоне. Фонари, тепловизоры приветствуются. Строгий тайминг и брифинг перед стартом.',
  'Москва',
  'Arena Tactical West',
  TIMESTAMPTZ '2026-09-20 21:30:00+03',
  (SELECT id FROM public.profiles ORDER BY created_at LIMIT 1),
  36,
  'https://images.unsplash.com/photo-1511512578047-dfb367046420?w=1200&q=80'
),
(
  'CQB Академия',
  'Интенсив по ближнему бою в закрытых помещениях. Короткие раунды, разбор ошибок, работа в двойках.',
  'Рязань',
  'HardPoint CQB',
  TIMESTAMPTZ '2026-09-18 17:00:00+03',
  (SELECT id FROM public.profiles ORDER BY created_at LIMIT 1),
  24,
  'https://images.unsplash.com/photo-1542751371-adc38448a05e?w=1200&q=80'
),
(
  'Лесной рейд',
  'Долгая сцена в лесном секторе с задачами на разведку и захват точек. Рекомендуется камуфляж и запас воды.',
  'Казань',
  'Полигон «Дубрава»',
  TIMESTAMPTZ '2026-09-27 10:00:00+03',
  (SELECT id FROM public.profiles ORDER BY created_at LIMIT 1),
  60,
  'https://images.unsplash.com/photo-1448375240586-882707db888b?w=1200&q=80'
),
(
  'Волжский рубеж',
  'Открытый матч с классическими правилами. Регистрация на месте закрывается за 30 минут до старта.',
  'Нижний Новгород',
  'Стрелковый комплекс «Волга»',
  TIMESTAMPTZ '2026-10-04 12:00:00+03',
  (SELECT id FROM public.profiles ORDER BY created_at LIMIT 1),
  40,
  'https://images.unsplash.com/photo-1552820728-8b83bb6b773f?w=1200&q=80'
),
(
  'Северный фронт',
  'Милсим-сценарий с ролями отделений и связью. Нужна команда от 4 человек или свободная запись в резерв.',
  'Санкт-Петербург',
  'Полигон «Форт»',
  TIMESTAMPTZ '2026-10-11 09:30:00+03',
  (SELECT id FROM public.profiles ORDER BY created_at LIMIT 1),
  72,
  'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=1200&q=80'
),
(
  'Тактический спринт',
  'Короткие динамичные раунды для разминки сезона. Идеально для новичков и отработки коммуникации.',
  'Санкт-Петербург',
  'Urban Range Spb',
  TIMESTAMPTZ '2026-09-22 19:00:00+03',
  (SELECT id FROM public.profiles ORDER BY created_at LIMIT 1),
  28,
  'https://images.unsplash.com/photo-1614294148960-9aa74082b310?w=1200&q=80'
);
