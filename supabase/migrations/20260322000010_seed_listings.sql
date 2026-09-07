-- ============================================================
-- Seed: 10 marketplace listings (requires ≥1 profile + categories)
-- Run AFTER: 20260322000007, 000008, 000009
-- ============================================================

-- Remove previous demo listings by stable ids
DELETE FROM public.listing_images
WHERE listing_id IN (
  SELECT id FROM public.listings
  WHERE id IN (
    'b1000000-0000-4000-8000-000000000001',
    'b1000000-0000-4000-8000-000000000002',
    'b1000000-0000-4000-8000-000000000003',
    'b1000000-0000-4000-8000-000000000004',
    'b1000000-0000-4000-8000-000000000005',
    'b1000000-0000-4000-8000-000000000006',
    'b1000000-0000-4000-8000-000000000007',
    'b1000000-0000-4000-8000-000000000008',
    'b1000000-0000-4000-8000-000000000009',
    'b1000000-0000-4000-8000-000000000010'
  )
);

DELETE FROM public.listings
WHERE id IN (
  'b1000000-0000-4000-8000-000000000001',
  'b1000000-0000-4000-8000-000000000002',
  'b1000000-0000-4000-8000-000000000003',
  'b1000000-0000-4000-8000-000000000004',
  'b1000000-0000-4000-8000-000000000005',
  'b1000000-0000-4000-8000-000000000006',
  'b1000000-0000-4000-8000-000000000007',
  'b1000000-0000-4000-8000-000000000008',
  'b1000000-0000-4000-8000-000000000009',
  'b1000000-0000-4000-8000-000000000010'
);

WITH seller AS (
  SELECT id, city FROM public.profiles ORDER BY created_at LIMIT 1
)
INSERT INTO public.listings (
  id,
  seller_id,
  category_id,
  title,
  description,
  price,
  city,
  condition,
  status,
  views_count,
  is_promoted
)
SELECT * FROM (VALUES
  (
    'b1000000-0000-4000-8000-000000000001'::uuid,
    (SELECT id FROM seller),
    'a2000000-0000-4000-8000-000000000011'::uuid,
    'AEG M4 Cyma CM.028',
    'Рабочий привод, аккум + зарядка в комплекте. Ходы ровные, после профилактики. Отдам с двумя mid-cap магазинами.',
    18500::numeric,
    COALESCE((SELECT city FROM seller), 'Москва'),
    'used',
    'active',
    42,
    false
  ),
  (
    'b1000000-0000-4000-8000-000000000002'::uuid,
    (SELECT id FROM seller),
    'a2000000-0000-4000-8000-000000000012'::uuid,
    'GBB Glock 17 WE',
    'Газовый пистолет, один магазин. Мелкие потёртости на затворе. Для CQB / тренировок.',
    12000::numeric,
    COALESCE((SELECT city FROM seller), 'Москва'),
    'used',
    'active',
    28,
    true
  ),
  (
    'b1000000-0000-4000-8000-000000000003'::uuid,
    (SELECT id FROM seller),
    'a2000000-0000-4000-8000-000000000022'::uuid,
    'Коллиматор Vector Optics',
    'Открытый коллиматор, крепление 22 мм. Светят все точки, влагозащита ок. Чехол в комплекте.',
    6500::numeric,
    'Санкт-Петербург',
    'like_new',
    'active',
    15,
    false
  ),
  (
    'b1000000-0000-4000-8000-000000000004'::uuid,
    (SELECT id FROM seller),
    'a2000000-0000-4000-8000-000000000021'::uuid,
    'Оптический прицел 3-9x40',
    'Классика для DMR/снайперки. Кольца в комплекте. Сетка чёткая, без люфтов на барабанах.',
    4900::numeric,
    'Москва',
    'used',
    'active',
    19,
    false
  ),
  (
    'b1000000-0000-4000-8000-000000000005'::uuid,
    (SELECT id FROM seller),
    'a2000000-0000-4000-8000-000000000031'::uuid,
    'Плитоносец + мягкие плиты',
    'Размер M. Цвет multicam. Мягкие пули (имитация) + подсумки под магазины. Состояние хорошее.',
    9800::numeric,
    'Казань',
    'used',
    'active',
    33,
    false
  ),
  (
    'b1000000-0000-4000-8000-000000000006'::uuid,
    (SELECT id FROM seller),
    'a2000000-0000-4000-8000-000000000032'::uuid,
    'Разгрузка Chest Rig',
    'Лёгкая нагрудная разгрузка, 3 подсумка под mid-cap. Регулируемые лямки. Почти не носили.',
    4200::numeric,
    'Рязань',
    'like_new',
    'active',
    11,
    false
  ),
  (
    'b1000000-0000-4000-8000-000000000007'::uuid,
    (SELECT id FROM seller),
    'a2000000-0000-4000-8000-000000000041'::uuid,
    'Костюм Gorka / форма',
    'Размер 50-52. После одной игры. Без дыр и пятен. Отдам пояс в подарок.',
    5500::numeric,
    'Москва',
    'like_new',
    'active',
    22,
    false
  ),
  (
    'b1000000-0000-4000-8000-000000000008'::uuid,
    (SELECT id FROM seller),
    'a2000000-0000-4000-8000-000000000051'::uuid,
    'Магазины mid-cap M4 ×5',
    'Пять mid-cap магазинов под M4/AR. Все рабочие, пружины живые. Можно по отдельности.',
    3500::numeric,
    'Нижний Новгород',
    'used',
    'active',
    17,
    false
  ),
  (
    'b1000000-0000-4000-8000-000000000009'::uuid,
    (SELECT id FROM seller),
    'a2000000-0000-4000-8000-000000000052'::uuid,
    'АКБ LiPo 11.1V + зарядка',
    'Два стика 11.1V и балансная зарядка. Аккумуляторы держат, без вздутий. Для AEG.',
    3900::numeric,
    'Москва',
    'used',
    'active',
    25,
    false
  ),
  (
    'b1000000-0000-4000-8000-000000000010'::uuid,
    (SELECT id FROM seller),
    'a2000000-0000-4000-8000-000000000053'::uuid,
    'Шары 0.25г — 5 кг',
    'Белые шары 0.25, мешок 5 кг. Упаковка целая, не вскрывали. Самовывоз или ТК.',
    2800::numeric,
    'Санкт-Петербург',
    'new',
    'active',
    9,
    false
  )
) AS v(
  id, seller_id, category_id, title, description, price, city, condition, status, views_count, is_promoted
)
WHERE (SELECT id FROM seller) IS NOT NULL;

-- Cover images (only if listings exist)
INSERT INTO public.listing_images (id, listing_id, url, sort_order)
SELECT v.id, v.listing_id, v.url, v.sort_order
FROM (VALUES
  ('b3000000-0000-4000-8000-000000000001'::uuid, 'b1000000-0000-4000-8000-000000000001'::uuid, 'https://images.unsplash.com/photo-1595590424283-b8f17842773f?w=1200&q=80', 0),
  ('b3000000-0000-4000-8000-000000000002'::uuid, 'b1000000-0000-4000-8000-000000000002'::uuid, 'https://images.unsplash.com/photo-1595590424283-b8f17842773f?w=1200&q=80', 0),
  ('b3000000-0000-4000-8000-000000000003'::uuid, 'b1000000-0000-4000-8000-000000000003'::uuid, 'https://images.unsplash.com/photo-1516035069371-29a1b244cc32?w=1200&q=80', 0),
  ('b3000000-0000-4000-8000-000000000004'::uuid, 'b1000000-0000-4000-8000-000000000004'::uuid, 'https://images.unsplash.com/photo-1516035069371-29a1b244cc32?w=1200&q=80', 0),
  ('b3000000-0000-4000-8000-000000000005'::uuid, 'b1000000-0000-4000-8000-000000000005'::uuid, 'https://images.unsplash.com/photo-1578662996442-48f60103fc96?w=1200&q=80', 0),
  ('b3000000-0000-4000-8000-000000000006'::uuid, 'b1000000-0000-4000-8000-000000000006'::uuid, 'https://images.unsplash.com/photo-1578662996442-48f60103fc96?w=1200&q=80', 0),
  ('b3000000-0000-4000-8000-000000000007'::uuid, 'b1000000-0000-4000-8000-000000000007'::uuid, 'https://images.unsplash.com/photo-1553062407-98eeb64c6a62?w=1200&q=80', 0),
  ('b3000000-0000-4000-8000-000000000008'::uuid, 'b1000000-0000-4000-8000-000000000008'::uuid, 'https://images.unsplash.com/photo-1581091226825-a6a2a5aee158?w=1200&q=80', 0),
  ('b3000000-0000-4000-8000-000000000009'::uuid, 'b1000000-0000-4000-8000-000000000009'::uuid, 'https://images.unsplash.com/photo-1581091226825-a6a2a5aee158?w=1200&q=80', 0),
  ('b3000000-0000-4000-8000-000000000010'::uuid, 'b1000000-0000-4000-8000-000000000010'::uuid, 'https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=1200&q=80', 0)
) AS v(id, listing_id, url, sort_order)
WHERE EXISTS (SELECT 1 FROM public.listings l WHERE l.id = v.listing_id)
ON CONFLICT (id) DO UPDATE
SET url = EXCLUDED.url,
    sort_order = EXCLUDED.sort_order;
