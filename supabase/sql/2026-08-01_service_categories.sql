-- Service categories: organize the services catalog (Hair/Beauty/Spa...) the
-- same way products already use `categories`. Idempotent: safe to run
-- multiple times and on environments at different migration stages.
-- Existing services are left uncategorized (category_id null) so nothing
-- currently sold breaks; the manager assigns categories afterwards.

create table if not exists public.service_categories (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  description text,
  image_url text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'service_categories_company_name_unique'
      and conrelid = 'public.service_categories'::regclass
  ) then
    alter table public.service_categories
      add constraint service_categories_company_name_unique unique (company_id, name);
  end if;
end
$$;

create index if not exists idx_service_categories_company_id
  on public.service_categories(company_id);

drop trigger if exists trg_service_categories_updated_at on public.service_categories;
create trigger trg_service_categories_updated_at
before update on public.service_categories
for each row execute function public.set_updated_at();

-- services: link to a category (nullable -> existing rows stay valid), plus
-- optional catalog-level metadata for a suggested default provider and an
-- indicative commission. These are pre-fill hints only: the authoritative
-- provider/commission assignment still happens per order line in
-- service_order_items, unchanged by this migration.
alter table public.services
  add column if not exists category_id uuid references public.service_categories(id) on delete set null;
alter table public.services
  add column if not exists image_url text;
alter table public.services
  add column if not exists default_provider_id uuid references public.users(id) on delete set null;
alter table public.services
  add column if not exists commission_type text;
alter table public.services
  add column if not exists commission_value numeric(12, 4);

alter table public.services
  drop constraint if exists services_commission_type_check;
alter table public.services
  add constraint services_commission_type_check
  check (commission_type is null or commission_type in ('fixed', 'percentage'));

alter table public.services
  drop constraint if exists services_commission_value_check;
alter table public.services
  add constraint services_commission_value_check
  check (
    commission_value is null
    or (commission_value >= 0 and (commission_type <> 'percentage' or commission_value <= 100))
  );

create index if not exists idx_services_category_id on public.services(company_id, category_id);

-- RLS: mirrors services_* (everyone in company can read, manager manages
-- the catalog).
alter table public.service_categories enable row level security;

drop policy if exists service_categories_select_company on public.service_categories;
create policy service_categories_select_company
on public.service_categories
for select
using (company_id = public.current_company_id());

drop policy if exists service_categories_insert_manager on public.service_categories;
create policy service_categories_insert_manager
on public.service_categories
for insert
with check (
  company_id = public.current_company_id()
  and public.is_manager()
);

drop policy if exists service_categories_update_manager on public.service_categories;
create policy service_categories_update_manager
on public.service_categories
for update
using (
  company_id = public.current_company_id()
  and public.is_manager()
)
with check (
  company_id = public.current_company_id()
  and public.is_manager()
);

drop policy if exists service_categories_delete_manager on public.service_categories;
create policy service_categories_delete_manager
on public.service_categories
for delete
using (
  company_id = public.current_company_id()
  and public.is_manager()
);
