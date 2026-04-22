-- Add per-company feature flags (jsonb)
-- Example shape:
-- {
--   "stock": true,
--   "vente": true,
--   "reservation": false,
--   "service": true
-- }

alter table if exists public.companies
  add column if not exists features jsonb;

update public.companies
set features = '{}'::jsonb
where features is null;

alter table if exists public.companies
  alter column features set default '{}'::jsonb;

alter table if exists public.companies
  alter column features set not null;
