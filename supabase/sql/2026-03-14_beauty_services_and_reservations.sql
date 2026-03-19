-- Beauty module: services, clients, reservations, service orders, and ticket-ready data.
-- This migration is idempotent and only adds missing structures.

create extension if not exists "pgcrypto";

-- 1) Catalog of beauty services.
create table if not exists public.services (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  description text,
  price numeric(12,2) not null default 0,
  duration_minutes integer,
  created_by uuid references public.users(id) on delete set null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Ensure new service fields exist for already-provisioned environments.
alter table public.services add column if not exists price numeric(12,2);
alter table public.services add column if not exists duration_minutes integer;
alter table public.services add column if not exists created_by uuid;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'services_created_by_fkey'
      and conrelid = 'public.services'::regclass
  ) then
    alter table public.services
      add constraint services_created_by_fkey
      foreign key (created_by)
      references public.users(id)
      on delete set null;
  end if;
end
$$;

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'services'
      and column_name = 'base_price'
  ) then
    execute '
      update public.services
      set price = coalesce(price, base_price, 0)
      where price is null
    ';
  else
    update public.services
    set price = coalesce(price, 0)
    where price is null;
  end if;
end
$$;

update public.services
set created_by = auth.uid()
where created_by is null
  and auth.uid() is not null;

alter table public.services alter column price set default 0;
alter table public.services alter column price set not null;

alter table public.services
  drop constraint if exists services_price_check;
alter table public.services
  add constraint services_price_check
  check (price >= 0);

alter table public.services
  drop constraint if exists services_duration_minutes_check;
alter table public.services
  add constraint services_duration_minutes_check
  check (duration_minutes is null or duration_minutes > 0);

-- 2) Client registry for salon workflows.
create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  full_name text not null,
  phone text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 3) Reservations booked by phone.
create table if not exists public.reservations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  client_id uuid references public.clients(id) on delete set null,
  client_name text not null,
  phone text,
  service_id uuid not null references public.services(id) on delete restrict,
  reserved_at timestamptz not null,
  status text not null default 'pending',
  notes text,
  created_by uuid references public.users(id) on delete set null,
  converted_order_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 4) Service checkout header.
create table if not exists public.service_orders (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  client_id uuid references public.clients(id) on delete set null,
  client_name text not null,
  cashier_id uuid references public.users(id) on delete set null,
  cashier_name text,
  reservation_id uuid references public.reservations(id) on delete set null,
  ticket_number text,
  payment_method text,
  payment_status text not null default 'paid',
  subtotal_amount numeric(12,2) not null default 0,
  discount_amount numeric(12,2) not null default 0,
  total_amount numeric(12,2) not null default 0,
  paid_amount numeric(12,2) not null default 0,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 5) Service checkout lines.
create table if not exists public.service_order_items (
  id uuid primary key default gen_random_uuid(),
  service_order_id uuid not null references public.service_orders(id) on delete cascade,
  service_id uuid references public.services(id) on delete set null,
  service_name text not null,
  unit_price numeric(12,2) not null default 0,
  quantity integer not null default 1,
  line_total numeric(12,2) not null default 0,
  created_at timestamptz not null default now()
);

-- Add late FK when table existed before this migration.
do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'reservations'
      and column_name = 'converted_order_id'
  ) and not exists (
    select 1
    from pg_constraint
    where conname = 'reservations_converted_order_id_fkey'
      and conrelid = 'public.reservations'::regclass
  ) then
    alter table public.reservations
      add constraint reservations_converted_order_id_fkey
      foreign key (converted_order_id)
      references public.service_orders(id)
      on delete set null;
  end if;
end
$$;

-- Data integrity constraints.
alter table public.reservations
  drop constraint if exists reservations_status_check;
alter table public.reservations
  add constraint reservations_status_check
  check (status in ('pending', 'confirmed', 'completed', 'cancelled', 'no_show'));

alter table public.service_orders
  drop constraint if exists service_orders_payment_status_check;
alter table public.service_orders
  add constraint service_orders_payment_status_check
  check (payment_status in ('unpaid', 'partial', 'paid', 'refunded'));

alter table public.service_orders
  drop constraint if exists service_orders_amounts_check;
alter table public.service_orders
  add constraint service_orders_amounts_check
  check (
    subtotal_amount >= 0
    and discount_amount >= 0
    and total_amount >= 0
    and paid_amount >= 0
    and total_amount = subtotal_amount - discount_amount
  );

alter table public.service_order_items
  drop constraint if exists service_order_items_quantity_check;
alter table public.service_order_items
  add constraint service_order_items_quantity_check
  check (quantity > 0);

alter table public.service_order_items
  drop constraint if exists service_order_items_line_total_check;
alter table public.service_order_items
  add constraint service_order_items_line_total_check
  check (line_total >= 0);

-- Uniques.
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'services_company_name_unique'
      and conrelid = 'public.services'::regclass
  ) then
    alter table public.services
      add constraint services_company_name_unique unique (company_id, name);
  end if;
end
$$;

create unique index if not exists uq_service_orders_company_ticket
on public.service_orders(company_id, ticket_number)
where ticket_number is not null;

-- Performance indexes.
create index if not exists idx_services_company_id on public.services(company_id);
create index if not exists idx_services_active on public.services(company_id, is_active);
create index if not exists idx_clients_company_id on public.clients(company_id);
create index if not exists idx_clients_phone on public.clients(company_id, phone);
create index if not exists idx_reservations_company_id on public.reservations(company_id);
create index if not exists idx_reservations_reserved_at on public.reservations(company_id, reserved_at);
create index if not exists idx_reservations_status on public.reservations(company_id, status);
create index if not exists idx_service_orders_company_id on public.service_orders(company_id);
create index if not exists idx_service_orders_created_at on public.service_orders(company_id, created_at desc);
create index if not exists idx_service_order_items_order_id on public.service_order_items(service_order_id);

-- Reuse central updated_at trigger function already in project.
drop trigger if exists trg_services_updated_at on public.services;
create trigger trg_services_updated_at
before update on public.services
for each row execute function public.set_updated_at();

drop trigger if exists trg_clients_updated_at on public.clients;
create trigger trg_clients_updated_at
before update on public.clients
for each row execute function public.set_updated_at();

drop trigger if exists trg_reservations_updated_at on public.reservations;
create trigger trg_reservations_updated_at
before update on public.reservations
for each row execute function public.set_updated_at();

drop trigger if exists trg_service_orders_updated_at on public.service_orders;
create trigger trg_service_orders_updated_at
before update on public.service_orders
for each row execute function public.set_updated_at();

-- RLS.
alter table public.services enable row level security;
alter table public.clients enable row level security;
alter table public.reservations enable row level security;
alter table public.service_orders enable row level security;
alter table public.service_order_items enable row level security;

-- services: everyone in company can read; manager manages catalog.
drop policy if exists services_select_company on public.services;
create policy services_select_company
on public.services
for select
using (company_id = public.current_company_id());

drop policy if exists services_insert_manager on public.services;
create policy services_insert_manager
on public.services
for insert
with check (
  company_id = public.current_company_id()
  and coalesce(created_by, auth.uid()) = auth.uid()
  and public.is_manager()
);

drop policy if exists services_update_manager on public.services;
create policy services_update_manager
on public.services
for update
using (
  company_id = public.current_company_id()
  and public.is_manager()
)
with check (
  company_id = public.current_company_id()
  and public.is_manager()
);

drop policy if exists services_delete_manager on public.services;
create policy services_delete_manager
on public.services
for delete
using (
  company_id = public.current_company_id()
  and public.is_manager()
);

-- clients: cashier (seller) and manager can maintain clients in company.
drop policy if exists clients_select_company on public.clients;
create policy clients_select_company
on public.clients
for select
using (company_id = public.current_company_id());

drop policy if exists clients_insert_company on public.clients;
create policy clients_insert_company
on public.clients
for insert
with check (company_id = public.current_company_id());

drop policy if exists clients_update_company on public.clients;
create policy clients_update_company
on public.clients
for update
using (company_id = public.current_company_id())
with check (company_id = public.current_company_id());

drop policy if exists clients_delete_manager on public.clients;
create policy clients_delete_manager
on public.clients
for delete
using (
  company_id = public.current_company_id()
  and public.is_manager()
);

-- reservations: cashier and manager can create/update in company.
drop policy if exists reservations_select_company on public.reservations;
create policy reservations_select_company
on public.reservations
for select
using (company_id = public.current_company_id());

drop policy if exists reservations_insert_company on public.reservations;
create policy reservations_insert_company
on public.reservations
for insert
with check (
  company_id = public.current_company_id()
  and (
    public.is_manager()
    or coalesce(created_by, auth.uid()) = auth.uid()
  )
);

drop policy if exists reservations_update_company on public.reservations;
create policy reservations_update_company
on public.reservations
for update
using (company_id = public.current_company_id())
with check (company_id = public.current_company_id());

drop policy if exists reservations_delete_manager on public.reservations;
create policy reservations_delete_manager
on public.reservations
for delete
using (
  company_id = public.current_company_id()
  and public.is_manager()
);

-- service orders: manager sees all, seller sees own cashier orders.
drop policy if exists service_orders_select_company_role on public.service_orders;
create policy service_orders_select_company_role
on public.service_orders
for select
using (
  company_id = public.current_company_id()
  and (
    public.is_manager()
    or cashier_id = auth.uid()
  )
);

drop policy if exists service_orders_insert_company_role on public.service_orders;
create policy service_orders_insert_company_role
on public.service_orders
for insert
with check (
  company_id = public.current_company_id()
  and (
    public.is_manager()
    or coalesce(cashier_id, auth.uid()) = auth.uid()
  )
);

drop policy if exists service_orders_update_company_role on public.service_orders;
create policy service_orders_update_company_role
on public.service_orders
for update
using (
  company_id = public.current_company_id()
  and (
    public.is_manager()
    or cashier_id = auth.uid()
  )
)
with check (
  company_id = public.current_company_id()
  and (
    public.is_manager()
    or cashier_id = auth.uid()
  )
);

drop policy if exists service_orders_delete_manager on public.service_orders;
create policy service_orders_delete_manager
on public.service_orders
for delete
using (
  company_id = public.current_company_id()
  and public.is_manager()
);

-- order items rely on parent order access rules.
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
      and (
        public.is_manager()
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
      and (
        public.is_manager()
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
      and public.is_manager()
  )
)
with check (
  exists (
    select 1
    from public.service_orders so
    where so.id = service_order_items.service_order_id
      and so.company_id = public.current_company_id()
      and public.is_manager()
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
      and public.is_manager()
  )
);
