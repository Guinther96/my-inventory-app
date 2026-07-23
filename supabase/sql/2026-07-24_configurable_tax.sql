-- Configurable tax/fee system for product sales and service sales.
-- Idempotent: safe to run multiple times and on environments at different
-- migration stages.

-- 1) Companies: manager-configurable tax settings.
-- Disabled by default so existing companies keep selling without tax until
-- a manager explicitly opts in.
alter table public.companies
  add column if not exists tax_enabled boolean not null default false;
alter table public.companies
  add column if not exists tax_name text not null default 'Taxe';
alter table public.companies
  add column if not exists tax_type text not null default 'percentage';
alter table public.companies
  add column if not exists tax_value numeric(12, 4) not null default 0;
alter table public.companies
  add column if not exists tax_currency text;

alter table public.companies
  drop constraint if exists companies_tax_type_check;
alter table public.companies
  add constraint companies_tax_type_check
  check (tax_type in ('fixed', 'percentage'));

alter table public.companies
  drop constraint if exists companies_tax_value_check;
alter table public.companies
  add constraint companies_tax_value_check
  check (tax_value >= 0 and (tax_type <> 'percentage' or tax_value <= 100));

alter table public.companies
  drop constraint if exists companies_tax_currency_check;
alter table public.companies
  add constraint companies_tax_currency_check
  check (tax_currency is null or tax_currency in ('HTG', 'USD'));

alter table public.companies
  drop constraint if exists companies_tax_fixed_currency_check;
alter table public.companies
  add constraint companies_tax_fixed_currency_check
  check (tax_type = 'percentage' or tax_currency is not null);

-- companies_select_own / companies_update_own_manager_active (defined in
-- 2026-04-06_companies_status_realtime_feature_access.sql) already cover
-- read/write access to these new columns; no new policy needed.

-- 2) Product sales: header + line items, symmetrical to service_orders /
-- service_order_items. stock_movements stays the source of truth for stock;
-- sales/sale_items become the source of truth for subtotal/tax/total of a
-- checked-out cart, with the tax configuration frozen at sale time so that
-- historical receipts never change if company settings change later.
create table if not exists public.sales (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  cashier_id uuid references public.users(id) on delete set null,
  cashier_name text,
  payment_currency text not null default 'HTG',
  exchange_rate numeric(12, 4),
  subtotal_amount numeric(12, 2) not null default 0,
  tax_enabled boolean not null default false,
  tax_name text,
  tax_type text,
  tax_value numeric(12, 4),
  tax_amount numeric(12, 2) not null default 0,
  total_amount numeric(12, 2) not null default 0,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.sale_items (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  product_name text not null,
  quantity integer not null default 1,
  unit_price numeric(12, 2) not null default 0,
  product_currency text not null default 'HTG',
  line_total numeric(12, 2) not null default 0,
  stock_movement_id uuid references public.stock_movements(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.sales
  drop constraint if exists sales_payment_currency_check;
alter table public.sales
  add constraint sales_payment_currency_check
  check (payment_currency in ('HTG', 'USD'));

alter table public.sales
  drop constraint if exists sales_tax_type_check;
alter table public.sales
  add constraint sales_tax_type_check
  check (tax_type is null or tax_type in ('fixed', 'percentage'));

alter table public.sales
  drop constraint if exists sales_amounts_check;
alter table public.sales
  add constraint sales_amounts_check
  check (
    subtotal_amount >= 0
    and tax_amount >= 0
    and total_amount >= 0
    and total_amount = round(subtotal_amount + tax_amount, 2)
  );

alter table public.sale_items
  drop constraint if exists sale_items_quantity_check;
alter table public.sale_items
  add constraint sale_items_quantity_check
  check (quantity > 0);

alter table public.sale_items
  drop constraint if exists sale_items_line_total_check;
alter table public.sale_items
  add constraint sale_items_line_total_check
  check (line_total >= 0);

alter table public.sale_items
  drop constraint if exists sale_items_product_currency_check;
alter table public.sale_items
  add constraint sale_items_product_currency_check
  check (product_currency in ('HTG', 'USD'));

create index if not exists idx_sales_company_id on public.sales(company_id);
create index if not exists idx_sales_created_at on public.sales(company_id, created_at desc);
create index if not exists idx_sale_items_sale_id on public.sale_items(sale_id);

drop trigger if exists trg_sales_updated_at on public.sales;
create trigger trg_sales_updated_at
before update on public.sales
for each row execute function public.set_updated_at();

-- RLS: mirrors the service_orders / service_order_items pattern (manager
-- sees everything in the company, cashier sees their own sales), gated by
-- the same 'sales' feature flag already used for stock_movements exits.
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;

drop policy if exists sales_select_company_role on public.sales;
create policy sales_select_company_role
on public.sales
for select
using (
  company_id = public.current_company_id()
  and public.current_company_can_access('sales')
  and (
    public.current_user_is_manager()
    or cashier_id = auth.uid()
  )
);

drop policy if exists sales_insert_company_role on public.sales;
create policy sales_insert_company_role
on public.sales
for insert
with check (
  company_id = public.current_company_id()
  and public.current_company_is_active()
  and public.current_company_can_access('sales')
  and (
    public.current_user_is_manager()
    or coalesce(cashier_id, auth.uid()) = auth.uid()
  )
);

drop policy if exists sales_update_manager on public.sales;
create policy sales_update_manager
on public.sales
for update
using (
  company_id = public.current_company_id()
  and public.current_user_is_manager()
  and public.current_company_can_access('sales')
)
with check (
  company_id = public.current_company_id()
  and public.current_user_is_manager()
  and public.current_company_can_access('sales')
);

drop policy if exists sales_delete_manager on public.sales;
create policy sales_delete_manager
on public.sales
for delete
using (
  company_id = public.current_company_id()
  and public.current_user_is_manager()
  and public.current_company_can_access('sales')
);

drop policy if exists sale_items_select_company_role on public.sale_items;
create policy sale_items_select_company_role
on public.sale_items
for select
using (
  exists (
    select 1
    from public.sales s
    where s.id = sale_items.sale_id
      and s.company_id = public.current_company_id()
      and public.current_company_can_access('sales')
      and (
        public.current_user_is_manager()
        or s.cashier_id = auth.uid()
      )
  )
);

drop policy if exists sale_items_insert_company_role on public.sale_items;
create policy sale_items_insert_company_role
on public.sale_items
for insert
with check (
  exists (
    select 1
    from public.sales s
    where s.id = sale_items.sale_id
      and s.company_id = public.current_company_id()
      and public.current_company_can_access('sales')
      and (
        public.current_user_is_manager()
        or s.cashier_id = auth.uid()
      )
  )
);

drop policy if exists sale_items_update_manager_only on public.sale_items;
create policy sale_items_update_manager_only
on public.sale_items
for update
using (
  exists (
    select 1
    from public.sales s
    where s.id = sale_items.sale_id
      and s.company_id = public.current_company_id()
      and public.current_company_can_access('sales')
      and public.current_user_is_manager()
  )
)
with check (
  exists (
    select 1
    from public.sales s
    where s.id = sale_items.sale_id
      and s.company_id = public.current_company_id()
      and public.current_company_can_access('sales')
      and public.current_user_is_manager()
  )
);

drop policy if exists sale_items_delete_manager_only on public.sale_items;
create policy sale_items_delete_manager_only
on public.sale_items
for delete
using (
  exists (
    select 1
    from public.sales s
    where s.id = sale_items.sale_id
      and s.company_id = public.current_company_id()
      and public.current_company_can_access('sales')
      and public.current_user_is_manager()
  )
);

-- 3) process_sale_checkout: atomic, server-side checkout of an entire cart.
-- Replaces the previous per-line process_sale_exit loop used by the POS
-- screen. process_sale_exit itself is left untouched (still used for manual
-- stock movements outside of checkout).
drop function if exists public.process_sale_checkout(uuid, jsonb, text, text);

create or replace function public.process_sale_checkout(
  p_company_id uuid,
  p_items jsonb,
  p_payment_currency text default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_user_company uuid;
  v_cashier_email text;
  v_company public.companies%rowtype;
  v_item jsonb;
  v_product public.products%rowtype;
  v_updated_product public.products%rowtype;
  v_product_id uuid;
  v_quantity integer;
  v_product_currency text;
  v_payment_currency text;
  v_rate numeric(12, 4);
  v_line_amount numeric(12, 2);
  v_exchange_rate_used numeric(12, 4);
  v_subtotal numeric(12, 2) := 0;
  v_tax_amount numeric(12, 2) := 0;
  v_total numeric(12, 2) := 0;
  v_sale public.sales%rowtype;
  v_movement public.stock_movements%rowtype;
  v_sale_item public.sale_items%rowtype;
  v_lines jsonb := '[]'::jsonb;
  v_next_qty integer;
  v_notes text;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  select u.company_id
  into v_user_company
  from public.users u
  where u.id = v_uid
  limit 1;

  if v_user_company is null or v_user_company <> p_company_id then
    raise exception 'Unauthorized company context';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Panier vide';
  end if;

  select *
  into v_company
  from public.companies
  where id = p_company_id;

  if not found then
    raise exception 'Company not found';
  end if;

  if p_payment_currency is not null and p_payment_currency not in ('HTG', 'USD') then
    raise exception 'Invalid payment currency';
  end if;
  v_payment_currency := coalesce(p_payment_currency, 'HTG');
  v_notes := nullif(btrim(coalesce(p_notes, '')), '');

  -- Pass 1: lock every product (ordered by id to avoid cross-cart
  -- deadlocks), decrement stock, accumulate the subtotal.
  for v_item in
    select value
    from jsonb_array_elements(p_items) as value
    order by (value->>'product_id')
  loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_quantity := (v_item->>'quantity')::integer;

    if v_quantity is null or v_quantity <= 0 then
      raise exception 'Quantity must be greater than zero';
    end if;

    select *
    into v_product
    from public.products p
    where p.id = v_product_id
      and p.company_id = p_company_id
    for update;

    if not found then
      raise exception 'Product not found in company';
    end if;

    v_product_currency := coalesce(v_product.currency, 'HTG');

    if v_payment_currency = v_product_currency then
      v_line_amount := round(v_product.price * v_quantity, 2);
      v_exchange_rate_used := null;
    else
      if v_rate is null then
        v_rate := v_company.usd_to_htg_rate;
        if v_rate is null then
          raise exception 'Taux de change non configure pour cette entreprise.';
        end if;
      end if;

      if v_product_currency = 'USD' and v_payment_currency = 'HTG' then
        v_line_amount := round(v_product.price * v_quantity * v_rate, 2);
      elsif v_product_currency = 'HTG' and v_payment_currency = 'USD' then
        v_line_amount := round((v_product.price * v_quantity) / v_rate, 2);
      else
        raise exception 'Unsupported currency conversion';
      end if;

      v_exchange_rate_used := v_rate;
    end if;

    v_subtotal := v_subtotal + v_line_amount;

    v_next_qty := greatest(coalesce(v_product.quantity, 0) - v_quantity, 0);
    update public.products p
    set quantity = v_next_qty,
        updated_at = now()
    where p.id = v_product_id
      and p.company_id = p_company_id
    returning * into v_updated_product;

    v_lines := v_lines || jsonb_build_object(
      'product_id', v_product_id,
      'product_name', v_product.name,
      'quantity', v_quantity,
      'unit_price', v_product.price,
      'product_currency', v_product_currency,
      'line_total', v_line_amount,
      'exchange_rate', v_exchange_rate_used
    );
  end loop;

  -- Tax: snapshot the company's tax configuration at this exact moment.
  -- Later changes to companies.tax_* must never affect this sale.
  if coalesce(v_company.tax_enabled, false) then
    if v_company.tax_type = 'fixed' then
      if coalesce(v_company.tax_currency, v_payment_currency) = v_payment_currency then
        v_tax_amount := round(v_company.tax_value, 2);
      else
        if v_rate is null then
          v_rate := v_company.usd_to_htg_rate;
          if v_rate is null then
            raise exception 'Taux de change non configure pour cette entreprise.';
          end if;
        end if;

        if v_company.tax_currency = 'USD' and v_payment_currency = 'HTG' then
          v_tax_amount := round(v_company.tax_value * v_rate, 2);
        elsif v_company.tax_currency = 'HTG' and v_payment_currency = 'USD' then
          v_tax_amount := round(v_company.tax_value / v_rate, 2);
        else
          raise exception 'Unsupported currency conversion';
        end if;
      end if;
    else
      v_tax_amount := round(v_subtotal * v_company.tax_value / 100, 2);
    end if;
  end if;

  v_total := round(v_subtotal + v_tax_amount, 2);

  select u.email
  into v_cashier_email
  from public.users u
  where u.id = v_uid;

  insert into public.sales (
    company_id,
    cashier_id,
    cashier_name,
    payment_currency,
    exchange_rate,
    subtotal_amount,
    tax_enabled,
    tax_name,
    tax_type,
    tax_value,
    tax_amount,
    total_amount,
    notes
  )
  values (
    p_company_id,
    v_uid,
    v_cashier_email,
    v_payment_currency,
    v_rate,
    v_subtotal,
    coalesce(v_company.tax_enabled, false),
    case when v_company.tax_enabled then v_company.tax_name else null end,
    case when v_company.tax_enabled then v_company.tax_type else null end,
    case when v_company.tax_enabled then v_company.tax_value else null end,
    v_tax_amount,
    v_total,
    v_notes
  )
  returning * into v_sale;

  -- Pass 2: persist each sale_item + its stock_movement, linked to the
  -- header created above.
  for v_item in select * from jsonb_array_elements(v_lines) loop
    insert into public.sale_items (
      sale_id,
      product_id,
      product_name,
      quantity,
      unit_price,
      product_currency,
      line_total
    )
    values (
      v_sale.id,
      (v_item->>'product_id')::uuid,
      v_item->>'product_name',
      (v_item->>'quantity')::integer,
      (v_item->>'unit_price')::numeric,
      v_item->>'product_currency',
      (v_item->>'line_total')::numeric
    )
    returning * into v_sale_item;

    insert into public.stock_movements (
      product_id,
      user_id,
      seller_id,
      type,
      quantity,
      notes,
      company_id,
      unit_price,
      product_currency,
      payment_currency,
      exchange_rate,
      amount_paid
    )
    values (
      (v_item->>'product_id')::uuid,
      v_uid,
      v_uid,
      'exit',
      (v_item->>'quantity')::integer,
      v_notes,
      p_company_id,
      (v_item->>'unit_price')::numeric,
      v_item->>'product_currency',
      v_payment_currency,
      (v_item->>'exchange_rate')::numeric,
      (v_item->>'line_total')::numeric
    )
    returning * into v_movement;

    update public.sale_items
    set stock_movement_id = v_movement.id
    where id = v_sale_item.id;
  end loop;

  return jsonb_build_object(
    'sale', to_jsonb(v_sale),
    'items', (
      select coalesce(jsonb_agg(to_jsonb(si)), '[]'::jsonb)
      from public.sale_items si
      where si.sale_id = v_sale.id
    )
  );
end;
$$;

revoke all on function public.process_sale_checkout(uuid, jsonb, text, text) from public;
grant execute on function public.process_sale_checkout(uuid, jsonb, text, text) to authenticated;

-- 4) Service orders: same tax snapshot fields, calculated client-side in
-- ServiceOrderService (existing pattern), enforced by the amounts check.
alter table public.service_orders
  add column if not exists tax_name text;
alter table public.service_orders
  add column if not exists tax_type text;
alter table public.service_orders
  add column if not exists tax_value numeric(12, 4);
alter table public.service_orders
  add column if not exists tax_amount numeric(12, 2) not null default 0;

alter table public.service_orders
  drop constraint if exists service_orders_tax_type_check;
alter table public.service_orders
  add constraint service_orders_tax_type_check
  check (tax_type is null or tax_type in ('fixed', 'percentage'));

alter table public.service_orders
  drop constraint if exists service_orders_amounts_check;
alter table public.service_orders
  add constraint service_orders_amounts_check
  check (
    subtotal_amount >= 0
    and discount_amount >= 0
    and tax_amount >= 0
    and total_amount >= 0
    and total_amount = round(subtotal_amount - discount_amount + tax_amount, 2)
  );
