begin;

create extension if not exists "pgcrypto";

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

alter table if exists public.companies
  add column if not exists status text;

alter table if exists public.companies
  add column if not exists updated_at timestamptz not null default now();

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'companies'
      and column_name = 'subscription_status'
  ) then
    execute $sql$
      update public.companies
      set status = case
        when lower(coalesce(status, '')) in ('active', 'actif') then 'active'
        when lower(coalesce(status, '')) in ('suspended', 'suspendu') then 'suspended'
        when lower(coalesce(subscription_status, '')) in ('active', 'trial', 'actif') then 'active'
        when lower(coalesce(subscription_status, '')) in ('suspended', 'suspendu') then 'suspended'
        else 'active'
      end
      where status is null
         or lower(status) not in ('active', 'suspended', 'actif', 'suspendu')
    $sql$;
  else
    update public.companies
    set status = case
      when lower(coalesce(status, '')) in ('active', 'actif') then 'active'
      when lower(coalesce(status, '')) in ('suspended', 'suspendu') then 'suspended'
      else 'active'
    end
    where status is null
       or lower(status) not in ('active', 'suspended', 'actif', 'suspendu');
  end if;
end
$$;

alter table if exists public.companies
  alter column status set default 'active';

alter table if exists public.companies
  alter column status set not null;

alter table if exists public.companies
  drop constraint if exists companies_status_check;

alter table if exists public.companies
  add constraint companies_status_check
  check (lower(status) in ('active', 'suspended', 'actif', 'suspendu'));

create index if not exists idx_companies_status on public.companies(status);

alter table if exists public.companies
  drop column if exists subscription_status;

create table if not exists public.company_features (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  feature_key text not null,
  enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  unique (company_id, feature_key)
);

alter table if exists public.company_features
  add column if not exists updated_at timestamptz not null default now();

create index if not exists idx_company_features_company_id
  on public.company_features(company_id);
create index if not exists idx_company_features_company_feature
  on public.company_features(company_id, feature_key);

drop trigger if exists trg_companies_updated_at on public.companies;
create trigger trg_companies_updated_at
before update on public.companies
for each row execute function public.set_updated_at();

drop trigger if exists trg_company_features_updated_at on public.company_features;
create trigger trg_company_features_updated_at
before update on public.company_features
for each row execute function public.set_updated_at();

create or replace function public.normalize_company_status(raw_status text)
returns text
language sql
immutable
as $$
  select case lower(coalesce(raw_status, 'active'))
    when 'actif' then 'active'
    when 'suspendu' then 'suspended'
    when 'suspended' then 'suspended'
    else 'active'
  end;
$$;

create or replace function public.current_user_is_manager()
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.role = 'manager'::public.app_role
  );
$$;

create or replace function public.company_is_active(p_company_id uuid)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from public.companies c
    where c.id = p_company_id
      and public.normalize_company_status(c.status) = 'active'
  );
$$;

create or replace function public.company_feature_enabled(
  p_company_id uuid,
  p_feature_key text
)
returns boolean
language sql
stable
as $$
  with normalized_feature as (
    select lower(trim(coalesce(p_feature_key, ''))) as key
  )
  select coalesce((
    select cf.enabled
    from public.company_features cf, normalized_feature nf
    where cf.company_id = p_company_id
      and lower(trim(cf.feature_key)) = nf.key
    limit 1
  ), true);
$$;

create or replace function public.company_has_any_feature(
  p_company_id uuid,
  p_feature_keys text[]
)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from unnest(p_feature_keys) as fk
    where public.company_feature_enabled(p_company_id, fk)
  );
$$;

create or replace function public.current_company_is_active()
returns boolean
language sql
stable
as $$
  select public.company_is_active(public.current_company_id());
$$;

create or replace function public.current_company_can_access(p_feature_key text)
returns boolean
language sql
stable
as $$
  select public.current_company_is_active()
         and public.company_feature_enabled(public.current_company_id(), p_feature_key);
$$;

create or replace function public.create_company_for_current_user(
  company_name text,
  company_email text
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $create_company$
declare
  v_uid uuid;
  v_existing_company_id uuid;
  v_last_attempt_at timestamptz;
  v_new_company_id uuid;
  v_clean_name text;
  v_clean_email text;
begin
  v_uid := auth.uid();

  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  select u.company_id
  into v_existing_company_id
  from public.users u
  where u.id = v_uid
  limit 1;

  if v_existing_company_id is not null then
    return v_existing_company_id;
  end if;

  select a.last_attempt_at
  into v_last_attempt_at
  from public.company_creation_attempts a
  where a.user_id = v_uid
  limit 1;

  if v_last_attempt_at is not null
     and now() - v_last_attempt_at < interval '30 seconds' then
    raise exception 'Too many onboarding attempts. Please retry in a few seconds.';
  end if;

  insert into public.company_creation_attempts(user_id, last_attempt_at)
  values (v_uid, now())
  on conflict (user_id)
  do update
  set last_attempt_at = excluded.last_attempt_at;

  v_clean_name := nullif(btrim(coalesce(company_name, '')), '');
  v_clean_email := nullif(lower(btrim(coalesce(company_email, ''))), '');

  if v_clean_name is null then
    raise exception 'Company name is required';
  end if;

  if v_clean_email is null then
    select lower(au.email)
    into v_clean_email
    from auth.users au
    where au.id = v_uid
    limit 1;
  end if;

  if v_clean_email is null then
    raise exception 'Company email is required';
  end if;

  insert into public.companies(name, email, status)
  values (v_clean_name, v_clean_email, 'active')
  returning id into v_new_company_id;

  insert into public.users(id, email, company_id, role)
  values (v_uid, v_clean_email, v_new_company_id, 'manager'::public.app_role)
  on conflict (id)
  do update
  set
    email = excluded.email,
    company_id = excluded.company_id,
    role = 'manager'::public.app_role;

  return v_new_company_id;
end;
$create_company$;

revoke all on function public.create_company_for_current_user(text, text) from public;
grant execute on function public.create_company_for_current_user(text, text) to authenticated;

alter table if exists public.companies enable row level security;
alter table if exists public.users enable row level security;
alter table if exists public.categories enable row level security;
alter table if exists public.products enable row level security;
alter table if exists public.stock_movements enable row level security;
alter table if exists public.services enable row level security;
alter table if exists public.clients enable row level security;
alter table if exists public.reservations enable row level security;
alter table if exists public.service_orders enable row level security;
alter table if exists public.service_order_items enable row level security;
alter table if exists public.company_features enable row level security;

-- companies

drop policy if exists companies_select_own on public.companies;
create policy companies_select_own
on public.companies
for select
using (id = public.current_company_id());

drop policy if exists companies_update_own on public.companies;
drop policy if exists companies_update_own_manager_active on public.companies;
create policy companies_update_own_manager_active
on public.companies
for update
using (
  id = public.current_company_id()
  and public.current_user_is_manager()
  and public.current_company_is_active()
)
with check (
  id = public.current_company_id()
  and public.current_user_is_manager()
);

-- users

drop policy if exists users_select_own_company on public.users;
create policy users_select_own_company
on public.users
for select
using (
  company_id = public.current_company_id()
  and public.current_company_is_active()
  and (public.current_user_is_manager() or id = auth.uid())
);

drop policy if exists users_insert_self on public.users;
create policy users_insert_self
on public.users
for insert
with check (
  id = auth.uid()
  and company_id = public.current_company_id()
  and public.current_company_is_active()
);

drop policy if exists users_update_self on public.users;
create policy users_update_self
on public.users
for update
using (
  company_id = public.current_company_id()
  and public.current_company_is_active()
  and (public.current_user_is_manager() or id = auth.uid())
)
with check (
  company_id = public.current_company_id()
  and public.current_company_is_active()
  and (public.current_user_is_manager() or id = auth.uid())
);

-- company_features

drop policy if exists company_features_select_own on public.company_features;
create policy company_features_select_own
on public.company_features
for select
using (
  company_id = public.current_company_id()
  and public.current_company_is_active()
);

drop policy if exists company_features_insert_manager on public.company_features;
create policy company_features_insert_manager
on public.company_features
for insert
with check (
  company_id = public.current_company_id()
  and public.current_user_is_manager()
);

drop policy if exists company_features_update_manager on public.company_features;
create policy company_features_update_manager
on public.company_features
for update
using (
  company_id = public.current_company_id()
  and public.current_user_is_manager()
)
with check (
  company_id = public.current_company_id()
  and public.current_user_is_manager()
);

drop policy if exists company_features_delete_manager on public.company_features;
create policy company_features_delete_manager
on public.company_features
for delete
using (
  company_id = public.current_company_id()
  and public.current_user_is_manager()
);

-- inventory

drop policy if exists categories_select_company on public.categories;
create policy categories_select_company
on public.categories
for select
using (
  company_id = public.current_company_id()
  and public.current_company_can_access('inventory')
);

drop policy if exists categories_insert_company on public.categories;
create policy categories_insert_company
on public.categories
for insert
with check (
  company_id = public.current_company_id()
  and public.current_user_is_manager()
  and public.current_company_can_access('inventory')
);

drop policy if exists categories_update_company on public.categories;
create policy categories_update_company
on public.categories
for update
using (
  company_id = public.current_company_id()
  and public.current_user_is_manager()
  and public.current_company_can_access('inventory')
)
with check (
  company_id = public.current_company_id()
  and public.current_user_is_manager()
  and public.current_company_can_access('inventory')
);

drop policy if exists categories_delete_company on public.categories;
create policy categories_delete_company
on public.categories
for delete
using (
  company_id = public.current_company_id()
  and public.current_user_is_manager()
  and public.current_company_can_access('inventory')
);

drop policy if exists products_select_company on public.products;
create policy products_select_company
on public.products
for select
using (
  company_id = public.current_company_id()
  and public.current_company_can_access('inventory')
);

drop policy if exists products_insert_company on public.products;
create policy products_insert_company
on public.products
for insert
with check (
  company_id = public.current_company_id()
  and public.current_user_is_manager()
  and public.current_company_can_access('inventory')
);

drop policy if exists products_update_company on public.products;
create policy products_update_company
on public.products
for update
using (
  company_id = public.current_company_id()
  and public.current_user_is_manager()
  and public.current_company_can_access('inventory')
)
with check (
  company_id = public.current_company_id()
  and public.current_user_is_manager()
  and public.current_company_can_access('inventory')
);

drop policy if exists products_delete_company on public.products;
create policy products_delete_company
on public.products
for delete
using (
  company_id = public.current_company_id()
  and public.current_user_is_manager()
  and public.current_company_can_access('inventory')
);

drop policy if exists movements_select_company on public.stock_movements;
create policy movements_select_company
on public.stock_movements
for select
using (
  company_id = public.current_company_id()
  and public.current_company_is_active()
  and public.company_has_any_feature(company_id, array['inventory', 'sales'])
);

drop policy if exists movements_insert_company on public.stock_movements;
create policy movements_insert_company
on public.stock_movements
for insert
with check (
  company_id = public.current_company_id()
  and public.current_company_is_active()
  and (user_id is null or user_id = auth.uid())
  and (
    (type = 'exit' and public.current_company_can_access('sales'))
    or (type in ('entry', 'adjustment') and public.current_company_can_access('inventory'))
  )
);

drop policy if exists movements_update_company on public.stock_movements;
create policy movements_update_company
on public.stock_movements
for update
using (
  company_id = public.current_company_id()
  and public.current_user_is_manager()
  and public.current_company_can_access('inventory')
)
with check (
  company_id = public.current_company_id()
  and public.current_user_is_manager()
  and public.current_company_can_access('inventory')
);

drop policy if exists movements_delete_company on public.stock_movements;
create policy movements_delete_company
on public.stock_movements
for delete
using (
  company_id = public.current_company_id()
  and public.current_user_is_manager()
  and public.current_company_can_access('inventory')
);

-- services module

drop policy if exists services_select_company on public.services;
create policy services_select_company
on public.services
for select
using (
  company_id = public.current_company_id()
  and public.current_company_can_access('services')
);

drop policy if exists services_insert_manager on public.services;
create policy services_insert_manager
on public.services
for insert
with check (
  company_id = public.current_company_id()
  and coalesce(created_by, auth.uid()) = auth.uid()
  and public.current_user_is_manager()
  and public.current_company_can_access('services')
);

drop policy if exists services_update_manager on public.services;
create policy services_update_manager
on public.services
for update
using (
  company_id = public.current_company_id()
  and public.current_user_is_manager()
  and public.current_company_can_access('services')
)
with check (
  company_id = public.current_company_id()
  and public.current_user_is_manager()
  and public.current_company_can_access('services')
);

drop policy if exists services_delete_manager on public.services;
create policy services_delete_manager
on public.services
for delete
using (
  company_id = public.current_company_id()
  and public.current_user_is_manager()
  and public.current_company_can_access('services')
);

drop policy if exists clients_select_company on public.clients;
create policy clients_select_company
on public.clients
for select
using (
  company_id = public.current_company_id()
  and public.current_company_can_access('services')
);

drop policy if exists clients_insert_company on public.clients;
create policy clients_insert_company
on public.clients
for insert
with check (
  company_id = public.current_company_id()
  and public.current_company_can_access('services')
);

drop policy if exists clients_update_company on public.clients;
create policy clients_update_company
on public.clients
for update
using (
  company_id = public.current_company_id()
  and public.current_company_can_access('services')
)
with check (
  company_id = public.current_company_id()
  and public.current_company_can_access('services')
);

drop policy if exists clients_delete_manager on public.clients;
create policy clients_delete_manager
on public.clients
for delete
using (
  company_id = public.current_company_id()
  and public.current_user_is_manager()
  and public.current_company_can_access('services')
);

drop policy if exists reservations_select_company on public.reservations;
create policy reservations_select_company
on public.reservations
for select
using (
  company_id = public.current_company_id()
  and public.current_company_can_access('services')
);

drop policy if exists reservations_insert_company on public.reservations;
create policy reservations_insert_company
on public.reservations
for insert
with check (
  company_id = public.current_company_id()
  and public.current_company_can_access('services')
  and (
    public.current_user_is_manager()
    or coalesce(created_by, auth.uid()) = auth.uid()
  )
);

drop policy if exists reservations_update_company on public.reservations;
create policy reservations_update_company
on public.reservations
for update
using (
  company_id = public.current_company_id()
  and public.current_company_can_access('services')
)
with check (
  company_id = public.current_company_id()
  and public.current_company_can_access('services')
);

drop policy if exists reservations_delete_manager on public.reservations;
create policy reservations_delete_manager
on public.reservations
for delete
using (
  company_id = public.current_company_id()
  and public.current_user_is_manager()
  and public.current_company_can_access('services')
);

drop policy if exists service_orders_select_company_role on public.service_orders;
create policy service_orders_select_company_role
on public.service_orders
for select
using (
  company_id = public.current_company_id()
  and public.current_company_can_access('services')
  and (
    public.current_user_is_manager()
    or cashier_id = auth.uid()
  )
);

drop policy if exists service_orders_insert_company_role on public.service_orders;
create policy service_orders_insert_company_role
on public.service_orders
for insert
with check (
  company_id = public.current_company_id()
  and public.current_company_can_access('services')
  and (
    public.current_user_is_manager()
    or coalesce(cashier_id, auth.uid()) = auth.uid()
  )
);

drop policy if exists service_orders_update_company_role on public.service_orders;
create policy service_orders_update_company_role
on public.service_orders
for update
using (
  company_id = public.current_company_id()
  and public.current_company_can_access('services')
  and (
    public.current_user_is_manager()
    or cashier_id = auth.uid()
  )
)
with check (
  company_id = public.current_company_id()
  and public.current_company_can_access('services')
  and (
    public.current_user_is_manager()
    or cashier_id = auth.uid()
  )
);

drop policy if exists service_orders_delete_manager on public.service_orders;
create policy service_orders_delete_manager
on public.service_orders
for delete
using (
  company_id = public.current_company_id()
  and public.current_user_is_manager()
  and public.current_company_can_access('services')
);

drop policy if exists service_order_items_select_company_role on public.service_order_items;
create policy service_order_items_select_company_role
on public.service_order_items
for select
using (
  exists (
    select 1
    from public.service_orders so
    where so.id = service_order_items.service_order_id
      and so.company_id = public.current_company_id()
      and public.current_company_can_access('services')
      and (
        public.current_user_is_manager()
        or so.cashier_id = auth.uid()
      )
  )
);

drop policy if exists service_order_items_insert_company_role on public.service_order_items;
create policy service_order_items_insert_company_role
on public.service_order_items
for insert
with check (
  exists (
    select 1
    from public.service_orders so
    where so.id = service_order_items.service_order_id
      and so.company_id = public.current_company_id()
      and public.current_company_can_access('services')
      and (
        public.current_user_is_manager()
        or so.cashier_id = auth.uid()
      )
  )
);

drop policy if exists service_order_items_update_manager_only on public.service_order_items;
create policy service_order_items_update_manager_only
on public.service_order_items
for update
using (
  exists (
    select 1
    from public.service_orders so
    where so.id = service_order_items.service_order_id
      and so.company_id = public.current_company_id()
      and public.current_company_can_access('services')
      and public.current_user_is_manager()
  )
)
with check (
  exists (
    select 1
    from public.service_orders so
    where so.id = service_order_items.service_order_id
      and so.company_id = public.current_company_id()
      and public.current_company_can_access('services')
      and public.current_user_is_manager()
  )
);

drop policy if exists service_order_items_delete_manager_only on public.service_order_items;
create policy service_order_items_delete_manager_only
on public.service_order_items
for delete
using (
  exists (
    select 1
    from public.service_orders so
    where so.id = service_order_items.service_order_id
      and so.company_id = public.current_company_id()
      and public.current_company_can_access('services')
      and public.current_user_is_manager()
  )
);

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'companies'
  ) then
    execute 'alter publication supabase_realtime add table public.companies';
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'company_features'
  ) then
    execute 'alter publication supabase_realtime add table public.company_features';
  end if;
end
$$;

commit;
