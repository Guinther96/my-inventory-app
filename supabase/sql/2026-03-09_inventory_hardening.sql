create extension if not exists "pgcrypto";

create table if not exists public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  email text not null,
  subscription_status text not null default 'trial',
  created_at timestamptz not null default now()
);

create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  company_id uuid not null references public.companies(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  company_id uuid not null references public.companies(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  barcode text,
  image_url text,
  price numeric(12,2) not null default 0,
  quantity integer not null default 0,
  min_stock integer not null default 5,
  category_id uuid references public.categories(id) on delete set null,
  company_id uuid not null references public.companies(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  user_id uuid references public.users(id) on delete set null,
  type text not null,
  quantity integer not null,
  notes text,
  company_id uuid not null references public.companies(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.categories add column if not exists description text;

alter table public.products add column if not exists description text;
alter table public.products add column if not exists barcode text;
alter table public.products add column if not exists image_url text;
alter table public.products add column if not exists quantity integer;
alter table public.products add column if not exists min_stock integer;
alter table public.products add column if not exists updated_at timestamptz;

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'products'
      and column_name = 'quantity_in_stock'
  ) then
    execute '
      update public.products
      set quantity = coalesce(quantity, quantity_in_stock, 0)
      where quantity is null
    ';
  else
    update public.products
    set quantity = coalesce(quantity, 0)
    where quantity is null;
  end if;
end
$$;

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'products'
      and column_name = 'min_stock_alert'
  ) then
    execute '
      update public.products
      set min_stock = coalesce(min_stock, min_stock_alert, 5)
      where min_stock is null
    ';
  else
    update public.products
    set min_stock = coalesce(min_stock, 5)
    where min_stock is null;
  end if;
end
$$;

alter table public.products alter column quantity set default 0;
alter table public.products alter column quantity set not null;
alter table public.products alter column min_stock set default 5;
alter table public.products alter column min_stock set not null;
alter table public.products alter column updated_at set default now();
alter table public.products alter column updated_at set not null;

alter table public.stock_movements add column if not exists user_id uuid;
alter table public.stock_movements add column if not exists notes text;
alter table public.stock_movements add column if not exists type text;

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'stock_movements'
      and column_name = 'movement_type'
  ) then
    execute '
      update public.stock_movements
      set type = coalesce(type, movement_type)
      where type is null
    ';
  end if;

  update public.stock_movements
  set type = coalesce(type, 'adjustment')
  where type is null;

  update public.stock_movements
  set quantity = 1
  where quantity is null or quantity <= 0;
end
$$;

alter table public.stock_movements alter column type set not null;
alter table public.stock_movements alter column quantity set not null;

alter table public.stock_movements
  drop constraint if exists stock_movements_user_id_fkey;

alter table public.stock_movements
  add constraint stock_movements_user_id_fkey
  foreign key (user_id)
  references public.users(id)
  on delete set null;

alter table public.stock_movements
  drop constraint if exists stock_movements_type_check;

alter table public.stock_movements
  add constraint stock_movements_type_check
  check (type in ('entry', 'exit', 'adjustment'));

alter table public.stock_movements
  drop constraint if exists stock_movements_quantity_check;

alter table public.stock_movements
  add constraint stock_movements_quantity_check
  check (quantity > 0);

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'products_name_company_unique'
      and conrelid = 'public.products'::regclass
  ) then
    alter table public.products
      add constraint products_name_company_unique unique (company_id, name);
  end if;
end
$$;

create index if not exists idx_users_company_id on public.users(company_id);
create index if not exists idx_categories_company_id on public.categories(company_id);
create index if not exists idx_products_company_id on public.products(company_id);
create index if not exists idx_products_category_id on public.products(category_id);
create index if not exists idx_stock_movements_company_id on public.stock_movements(company_id);
create index if not exists idx_stock_movements_product_id on public.stock_movements(product_id);
create index if not exists idx_stock_movements_created_at on public.stock_movements(created_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_products_updated_at on public.products;
create trigger trg_products_updated_at
before update on public.products
for each row execute function public.set_updated_at();

alter table public.companies enable row level security;
alter table public.users enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.stock_movements enable row level security;

create or replace function public.current_company_id()
returns uuid
language sql
stable
as $$
  select u.company_id
  from public.users u
  where u.id = auth.uid()
  limit 1;
$$;

drop policy if exists companies_select_own on public.companies;
create policy companies_select_own
on public.companies
for select
using (id = public.current_company_id());

drop policy if exists companies_update_own on public.companies;
create policy companies_update_own
on public.companies
for update
using (id = public.current_company_id());

drop policy if exists users_select_own_company on public.users;
create policy users_select_own_company
on public.users
for select
using (company_id = public.current_company_id());

drop policy if exists users_insert_self on public.users;
create policy users_insert_self
on public.users
for insert
with check (id = auth.uid());

drop policy if exists users_update_self on public.users;
create policy users_update_self
on public.users
for update
using (id = auth.uid());

drop policy if exists categories_select_company on public.categories;
create policy categories_select_company
on public.categories
for select
using (company_id = public.current_company_id());

drop policy if exists categories_insert_company on public.categories;
create policy categories_insert_company
on public.categories
for insert
with check (company_id = public.current_company_id());

drop policy if exists categories_update_company on public.categories;
create policy categories_update_company
on public.categories
for update
using (company_id = public.current_company_id());

drop policy if exists categories_delete_company on public.categories;
create policy categories_delete_company
on public.categories
for delete
using (company_id = public.current_company_id());

drop policy if exists products_select_company on public.products;
create policy products_select_company
on public.products
for select
using (company_id = public.current_company_id());

drop policy if exists products_insert_company on public.products;
create policy products_insert_company
on public.products
for insert
with check (company_id = public.current_company_id());

drop policy if exists products_update_company on public.products;
create policy products_update_company
on public.products
for update
using (company_id = public.current_company_id());

drop policy if exists products_delete_company on public.products;
create policy products_delete_company
on public.products
for delete
using (company_id = public.current_company_id());

drop policy if exists movements_select_company on public.stock_movements;
create policy movements_select_company
on public.stock_movements
for select
using (company_id = public.current_company_id());

drop policy if exists movements_insert_company on public.stock_movements;
create policy movements_insert_company
on public.stock_movements
for insert
with check (
  company_id = public.current_company_id()
  and (user_id is null or user_id = auth.uid())
);

drop policy if exists movements_update_company on public.stock_movements;
create policy movements_update_company
on public.stock_movements
for update
using (company_id = public.current_company_id());

drop policy if exists movements_delete_company on public.stock_movements;
create policy movements_delete_company
on public.stock_movements
for delete
using (company_id = public.current_company_id());

create or replace function public.create_company_for_current_user(
  company_name text,
  company_email text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_company_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  insert into public.companies(name, email, subscription_status)
  values (company_name, company_email, 'trial')
  returning id into new_company_id;

  insert into public.users(id, email, company_id)
  values (auth.uid(), company_email, new_company_id)
  on conflict (id)
  do update set
    email = excluded.email,
    company_id = excluded.company_id;

  return new_company_id;
end;
$$;

grant execute on function public.create_company_for_current_user(text, text) to authenticated;
