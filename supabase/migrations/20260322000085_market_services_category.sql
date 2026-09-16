-- ============================================================
-- Marketplace: root category «Услуги» + subcategories
-- ============================================================

INSERT INTO public.categories (id, name, parent_id, icon, sort_order)
VALUES
  ('a1000000-0000-4000-8000-000000000007', 'Услуги', NULL, 'handyman', 55)
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name,
    parent_id = EXCLUDED.parent_id,
    icon = EXCLUDED.icon,
    sort_order = EXCLUDED.sort_order;

INSERT INTO public.categories (id, name, parent_id, icon, sort_order)
VALUES
  ('a2000000-0000-4000-8000-000000000071', 'Ремонт', 'a1000000-0000-4000-8000-000000000007', NULL, 71),
  ('a2000000-0000-4000-8000-000000000072', 'Тюнинг', 'a1000000-0000-4000-8000-000000000007', NULL, 72),
  ('a2000000-0000-4000-8000-000000000073', 'Аренда', 'a1000000-0000-4000-8000-000000000007', NULL, 73),
  ('a2000000-0000-4000-8000-000000000074', 'Обучение', 'a1000000-0000-4000-8000-000000000007', NULL, 74),
  ('a2000000-0000-4000-8000-000000000075', 'Другое', 'a1000000-0000-4000-8000-000000000007', NULL, 75)
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name,
    parent_id = EXCLUDED.parent_id,
    sort_order = EXCLUDED.sort_order;
