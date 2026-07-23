-- Multi-currency support (HTG / USD) for products, services, and sales.
-- Idempotent: safe to run multiple times and on environments at different
-- migration stages.

-- 1) Products: currency column, default HTG for existing rows.
alter table public.products
  add column if not exists currency text;

update public.products
set currency = 'HTG'
where currency is null;

alter table public.products
  alter column currency set default 'HTG';
alter table public.products
  alter column currency set not null;

alter table public.products
  drop constraint if exists products_currency_check;
alter table public.products
  add constraint products_currency_check
  check (currency in ('HTG', 'USD'));

-- 2) Services: same treatment.
alter table public.services
  add column if not exists currency text;

update public.services
set currency = 'HTG'
where currency is null;

alter table public.services
  alter column currency set default 'HTG';
alter table public.services
  alter column currency set not null;

alter table public.services
  drop constraint if exists services_currency_check;
alter table public.services
  add constraint services_currency_check
  check (currency in ('HTG', 'USD'));

-- 3) Companies: manager-configurable exchange rate (1 USD = X HTG).
-- Nullable: cross-currency payments are refused until a manager sets it.
alter table public.companies
  add column if not exists usd_to_htg_rate numeric(12, 4);

alter table public.companies
  drop constraint if exists companies_usd_to_htg_rate_check;
alter table public.companies
  add constraint companies_usd_to_htg_rate_check
  check (usd_to_htg_rate is null or usd_to_htg_rate > 0);

-- 4) Stock movements: snapshot pricing/payment info for sale exits.
-- Nullable so existing rows and non-exit movements (entry/adjustment) are
-- unaffected.
alter table public.stock_movements
  add column if not exists unit_price numeric(12, 2);
alter table public.stock_movements
  add column if not exists product_currency text;
alter table public.stock_movements
  add column if not exists payment_currency text;
alter table public.stock_movements
  add column if not exists exchange_rate numeric(12, 4);
alter table public.stock_movements
  add column if not exists amount_paid numeric(12, 2);

alter table public.stock_movements
  drop constraint if exists stock_movements_product_currency_check;
alter table public.stock_movements
  add constraint stock_movements_product_currency_check
  check (product_currency is null or product_currency in ('HTG', 'USD'));

alter table public.stock_movements
  drop constraint if exists stock_movements_payment_currency_check;
alter table public.stock_movements
  add constraint stock_movements_payment_currency_check
  check (payment_currency is null or payment_currency in ('HTG', 'USD'));

-- 5) Service order items: currency snapshot of the service at sale time.
alter table public.service_order_items
  add column if not exists currency text;

update public.service_order_items
set currency = 'HTG'
where currency is null;

alter table public.service_order_items
  alter column currency set default 'HTG';
alter table public.service_order_items
  alter column currency set not null;

alter table public.service_order_items
  drop constraint if exists service_order_items_currency_check;
alter table public.service_order_items
  add constraint service_order_items_currency_check
  check (currency in ('HTG', 'USD'));

-- 6) Service orders: payment currency + exchange rate used for the ticket.
alter table public.service_orders
  add column if not exists payment_currency text;

update public.service_orders
set payment_currency = 'HTG'
where payment_currency is null;

alter table public.service_orders
  alter column payment_currency set default 'HTG';
alter table public.service_orders
  alter column payment_currency set not null;

alter table public.service_orders
  drop constraint if exists service_orders_payment_currency_check;
alter table public.service_orders
  add constraint service_orders_payment_currency_check
  check (payment_currency in ('HTG', 'USD'));

alter table public.service_orders
  add column if not exists exchange_rate numeric(12, 4);

-- 7) process_sale_exit: server-side currency-aware sale recording.
-- The paid amount is always recomputed from the product price and the
-- company exchange rate stored in Supabase, never trusted from the client,
-- so a cashier client cannot under-report a sale.
-- The previous 4-argument overload is dropped first: since the new version
-- adds a 5th parameter, Postgres would otherwise keep both signatures around
-- and a 4-argument call would become ambiguous between them.
drop function if exists public.process_sale_exit(uuid, uuid, integer, text);

create or replace function public.process_sale_exit(
  p_company_id uuid,
  p_product_id uuid,
  p_quantity integer,
  p_notes text default null,
  p_payment_currency text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_user_company uuid;
  v_product public.products%rowtype;
  v_updated_product public.products%rowtype;
  v_movement public.stock_movements%rowtype;
  v_next_qty integer;
  v_product_currency text;
  v_payment_currency text;
  v_rate numeric(12, 4);
  v_amount_paid numeric(12, 2);
  v_exchange_rate_used numeric(12, 4);
begin
  v_uid := auth.uid();

  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Quantity must be greater than zero';
  end if;

  select u.company_id
  into v_user_company
  from public.users u
  where u.id = v_uid
  limit 1;

  if v_user_company is null or v_user_company <> p_company_id then
    raise exception 'Unauthorized company context';
  end if;

  select *
  into v_product
  from public.products p
  where p.id = p_product_id
    and p.company_id = p_company_id
  for update;

  if not found then
    raise exception 'Product not found in company';
  end if;

  v_product_currency := coalesce(v_product.currency, 'HTG');

  if p_payment_currency is not null and p_payment_currency not in ('HTG', 'USD') then
    raise exception 'Invalid payment currency';
  end if;

  v_payment_currency := coalesce(p_payment_currency, v_product_currency);

  if v_payment_currency = v_product_currency then
    v_amount_paid := round(v_product.price * p_quantity, 2);
    v_exchange_rate_used := null;
  else
    select c.usd_to_htg_rate
    into v_rate
    from public.companies c
    where c.id = p_company_id;

    if v_rate is null then
      raise exception 'Taux de change non configure pour cette entreprise.';
    end if;

    if v_product_currency = 'USD' and v_payment_currency = 'HTG' then
      v_amount_paid := round(v_product.price * p_quantity * v_rate, 2);
    elsif v_product_currency = 'HTG' and v_payment_currency = 'USD' then
      v_amount_paid := round((v_product.price * p_quantity) / v_rate, 2);
    else
      raise exception 'Unsupported currency conversion';
    end if;

    v_exchange_rate_used := v_rate;
  end if;

  v_next_qty := coalesce(v_product.quantity, 0) - p_quantity;
  if v_next_qty < 0 then
    v_next_qty := 0;
  end if;

  update public.products p
  set quantity = v_next_qty,
      updated_at = now()
  where p.id = p_product_id
    and p.company_id = p_company_id
  returning * into v_updated_product;

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
    p_product_id,
    v_uid,
    v_uid,
    'exit',
    p_quantity,
    nullif(btrim(coalesce(p_notes, '')), ''),
    p_company_id,
    v_product.price,
    v_product_currency,
    v_payment_currency,
    v_exchange_rate_used,
    v_amount_paid
  )
  returning * into v_movement;

  return jsonb_build_object(
    'product', to_jsonb(v_updated_product),
    'movement', to_jsonb(v_movement)
  );
end;
$$;

revoke all on function public.process_sale_exit(uuid, uuid, integer, text, text) from public;
grant execute on function public.process_sale_exit(uuid, uuid, integer, text, text) to authenticated;
