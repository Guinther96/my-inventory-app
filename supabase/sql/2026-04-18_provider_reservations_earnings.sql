-- Provider module: provider_reservations + provider_earnings
-- Idempotent – safe to run multiple times.
-- Uses a SEPARATE namespace (provider_reservations / provider_earnings)
-- to avoid any collision with the existing beauty "reservations" table.

begin;

-- ──────────────────────────────────────────────
-- 1. provider_reservations
-- ──────────────────────────────────────────────
create table if not exists public.provider_reservations (
  id              uuid        primary key default gen_random_uuid(),
  business_id     uuid        not null references public.companies(id) on delete cascade,
  provider_id     uuid        not null references public.users(id) on delete cascade,
  client_name     text        not null,
  service_name    text        not null,
  price           numeric(12,2) not null check (price > 0),
  date            date        not null,
  time            time        not null,
  status          text        not null default 'pending'
                              check (status in ('pending', 'completed', 'cancelled')),
  created_by      text        not null default 'provider'
                              check (created_by in ('provider', 'client')),
  created_at      timestamptz not null default now()
);

-- Unique: empêche double réservation même prestataire même date+heure
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'uq_provider_reservation_slot'
      and conrelid = 'public.provider_reservations'::regclass
  ) then
    alter table public.provider_reservations
      add constraint uq_provider_reservation_slot
      unique (provider_id, date, time);
  end if;
end
$$;

create index if not exists idx_prov_reservations_provider
  on public.provider_reservations(provider_id);
create index if not exists idx_prov_reservations_business
  on public.provider_reservations(business_id);
create index if not exists idx_prov_reservations_date
  on public.provider_reservations(provider_id, date desc);

-- ──────────────────────────────────────────────
-- 2. provider_earnings
-- ──────────────────────────────────────────────
create table if not exists public.provider_earnings (
  id              uuid        primary key default gen_random_uuid(),
  provider_id     uuid        not null references public.users(id) on delete cascade,
  reservation_id  uuid        not null references public.provider_reservations(id) on delete cascade,
  amount          numeric(12,2) not null check (amount > 0),
  created_at      timestamptz not null default now()
);

-- Empêche les doublons de gains par réservation
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'uq_provider_earning_reservation'
      and conrelid = 'public.provider_earnings'::regclass
  ) then
    alter table public.provider_earnings
      add constraint uq_provider_earning_reservation
      unique (reservation_id);
  end if;
end
$$;

create index if not exists idx_prov_earnings_provider
  on public.provider_earnings(provider_id);

-- ──────────────────────────────────────────────
-- 3. Trigger: création automatique d'un gain
--    quand status devient 'completed'
-- ──────────────────────────────────────────────
create or replace function public.fn_provider_reservation_completed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'completed' and old.status <> 'completed' then
    insert into public.provider_earnings (provider_id, reservation_id, amount)
    values (new.provider_id, new.id, new.price)
    on conflict (reservation_id) do nothing;  -- pas de doublon
  end if;
  return new;
end;
$$;

drop trigger if exists trg_provider_reservation_completed
  on public.provider_reservations;
create trigger trg_provider_reservation_completed
  after update on public.provider_reservations
  for each row execute function public.fn_provider_reservation_completed();

-- ──────────────────────────────────────────────
-- 4. RLS
-- ──────────────────────────────────────────────
alter table public.provider_reservations enable row level security;
alter table public.provider_earnings     enable row level security;

-- provider_reservations --

drop policy if exists prov_res_select on public.provider_reservations;
create policy prov_res_select
  on public.provider_reservations
  for select
  using (
    provider_id = auth.uid()
    or public.current_user_is_manager()
  );

drop policy if exists prov_res_insert on public.provider_reservations;
create policy prov_res_insert
  on public.provider_reservations
  for insert
  with check (
    provider_id = auth.uid()
    and business_id = public.current_company_id()
  );

drop policy if exists prov_res_update on public.provider_reservations;
create policy prov_res_update
  on public.provider_reservations
  for update
  using (
    provider_id = auth.uid()
    or public.current_user_is_manager()
  )
  with check (
    business_id = public.current_company_id()
  );

drop policy if exists prov_res_delete on public.provider_reservations;
create policy prov_res_delete
  on public.provider_reservations
  for delete
  using (
    provider_id = auth.uid()
    or public.current_user_is_manager()
  );

-- provider_earnings --

drop policy if exists prov_earn_select on public.provider_earnings;
create policy prov_earn_select
  on public.provider_earnings
  for select
  using (
    provider_id = auth.uid()
    or public.current_user_is_manager()
  );

-- Pas de insert/update/delete manuels: géré par le trigger SECURITY DEFINER.

-- ──────────────────────────────────────────────
-- 5. Realtime
-- ──────────────────────────────────────────────
alter table public.provider_reservations replica identity full;
alter table public.provider_earnings     replica identity full;

do $$
begin
  begin
    alter publication supabase_realtime add table public.provider_reservations;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.provider_earnings;
  exception when duplicate_object then null;
  end;
end
$$;

commit;
