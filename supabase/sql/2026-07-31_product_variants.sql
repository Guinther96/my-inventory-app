-- Universal product variant system (POS "fiche produit").
-- Adds product_variants (own sku/barcode/price/stock) and variant_attributes
-- (unlimited free-form attributes: couleur/taille for a boutique, duree/finition
-- for un barbershop, longueur/technique pour un studio de beaute...).
-- Idempotent: safe to run multiple times and on environments at different
-- migration stages. Nothing here removes or renames existing columns: a
-- product without variants keeps working exactly as before (products.quantity
-- stays authoritative for it), and process_sale_checkout stays backward
-- compatible for carts that only send product_id (no variant_id).

-- 1) Tables -------------------------------------------------------------
create table if not exists public.product_variants (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  sku text,
  barcode text,
  price numeric(12, 2) not null default 0,
  stock integer not null default 0,
  image_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.product_variants
  drop constraint if exists product_variants_price_check;
alter table public.product_variants
  add constraint product_variants_price_check
  check (price >= 0);

alter table public.product_variants
  drop constraint if exists product_variants_stock_check;
alter table public.product_variants
  add constraint product_variants_stock_check
  check (stock >= 0);

create index if not exists idx_product_variants_company_id
  on public.product_variants(company_id);
create index if not exists idx_product_variants_product_id
  on public.product_variants(product_id);

create table if not exists public.variant_attributes (
  id uuid primary key default gen_random_uuid(),
  variant_id uuid not null references public.product_variants(id) on delete cascade,
  attribute_name text not null,
  attribute_value text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_variant_attributes_variant_id
  on public.variant_attributes(variant_id);

drop trigger if exists trg_product_variants_updated_at on public.product_variants;
create trigger trg_product_variants_updated_at
before update on public.product_variants
for each row execute function public.set_updated_at();

-- 2) RLS: mirrors the products_* policies (company-scoped, any authenticated
-- member of the company can read/write, consistent with how products already
-- behave today).
alter table public.product_variants enable row level security;
alter table public.variant_attributes enable row level security;

drop policy if exists product_variants_select_company on public.product_variants;
create policy product_variants_select_company
on public.product_variants
for select
using (company_id = public.current_company_id());

drop policy if exists product_variants_insert_company on public.product_variants;
create policy product_variants_insert_company
on public.product_variants
for insert
with check (company_id = public.current_company_id());

drop policy if exists product_variants_update_company on public.product_variants;
create policy product_variants_update_company
on public.product_variants
for update
using (company_id = public.current_company_id())
with check (company_id = public.current_company_id());

drop policy if exists product_variants_delete_company on public.product_variants;
create policy product_variants_delete_company
on public.product_variants
for delete
using (company_id = public.current_company_id());

drop policy if exists variant_attributes_select_company on public.variant_attributes;
create policy variant_attributes_select_company
on public.variant_attributes
for select
using (
  exists (
    select 1 from public.product_variants pv
    where pv.id = variant_attributes.variant_id
      and pv.company_id = public.current_company_id()
  )
);

drop policy if exists variant_attributes_insert_company on public.variant_attributes;
create policy variant_attributes_insert_company
on public.variant_attributes
for insert
with check (
  exists (
    select 1 from public.product_variants pv
    where pv.id = variant_attributes.variant_id
      and pv.company_id = public.current_company_id()
  )
);

drop policy if exists variant_attributes_update_company on public.variant_attributes;
create policy variant_attributes_update_company
on public.variant_attributes
for update
using (
  exists (
    select 1 from public.product_variants pv
    where pv.id = variant_attributes.variant_id
      and pv.company_id = public.current_company_id()
  )
)
with check (
  exists (
    select 1 from public.product_variants pv
    where pv.id = variant_attributes.variant_id
      and pv.company_id = public.current_company_id()
  )
);

drop policy if exists variant_attributes_delete_company on public.variant_attributes;
create policy variant_attributes_delete_company
on public.variant_attributes
for delete
using (
  exists (
    select 1 from public.product_variants pv
    where pv.id = variant_attributes.variant_id
      and pv.company_id = public.current_company_id()
  )
);

-- 3) sale_items: remember which variant (and its attribute summary) was
-- actually sold, so receipts/history stay readable even if the variant is
-- edited or deleted later. Both columns are nullable: existing rows and
-- non-variant sales are unaffected.
alter table public.sale_items
  add column if not exists variant_id uuid references public.product_variants(id) on delete set null;
alter table public.sale_items
  add column if not exists variant_label text;

-- 4) process_sale_checkout: extend p_items to accept an optional
-- "variant_id" per line. When present, price/stock authority moves to
-- product_variants (own price, own stock, decremented instead of the parent
-- product's). When absent (existing behavior), everything works exactly as
-- before on public.products. This is purely additive: clients that keep
-- sending {product_id, quantity} are unaffected.
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
  v_variant public.product_variants%rowtype;
  v_variant_id uuid;
  v_variant_label text;
  v_product_id uuid;
  v_quantity integer;
  v_unit_price numeric(12, 2);
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

  -- Pass 1: lock every product (and its variant, if any), ordered by
  -- product_id then variant_id to avoid cross-cart deadlocks, decrement
  -- stock at the right level, accumulate the subtotal.
  for v_item in
    select value
    from jsonb_array_elements(p_items) as value
    order by (value->>'product_id'), (value->>'variant_id')
  loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_quantity := (v_item->>'quantity')::integer;
    v_variant_id := nullif(v_item->>'variant_id', '')::uuid;

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
    v_variant_label := null;

    if v_variant_id is not null then
      select *
      into v_variant
      from public.product_variants pv
      where pv.id = v_variant_id
        and pv.product_id = v_product_id
        and pv.company_id = p_company_id
      for update;

      if not found then
        raise exception 'Variant not found for this product';
      end if;

      if v_variant.stock < v_quantity then
        raise exception 'Stock insuffisant pour cette variante de %', v_product.name;
      end if;

      v_unit_price := v_variant.price;

      update public.product_variants pv
      set stock = pv.stock - v_quantity,
          updated_at = now()
      where pv.id = v_variant_id;

      select coalesce(
        string_agg(va.attribute_name || ': ' || va.attribute_value, ', ' order by va.attribute_name),
        ''
      )
      into v_variant_label
      from public.variant_attributes va
      where va.variant_id = v_variant_id;
    else
      v_unit_price := v_product.price;

      v_next_qty := greatest(coalesce(v_product.quantity, 0) - v_quantity, 0);
      update public.products p
      set quantity = v_next_qty,
          updated_at = now()
      where p.id = v_product_id
        and p.company_id = p_company_id;
    end if;

    if v_payment_currency = v_product_currency then
      v_line_amount := round(v_unit_price * v_quantity, 2);
      v_exchange_rate_used := null;
    else
      if v_rate is null then
        v_rate := v_company.usd_to_htg_rate;
        if v_rate is null then
          raise exception 'Taux de change non configure pour cette entreprise.';
        end if;
      end if;

      if v_product_currency = 'USD' and v_payment_currency = 'HTG' then
        v_line_amount := round(v_unit_price * v_quantity * v_rate, 2);
      elsif v_product_currency = 'HTG' and v_payment_currency = 'USD' then
        v_line_amount := round((v_unit_price * v_quantity) / v_rate, 2);
      else
        raise exception 'Unsupported currency conversion';
      end if;

      v_exchange_rate_used := v_rate;
    end if;

    v_subtotal := v_subtotal + v_line_amount;

    v_lines := v_lines || jsonb_build_object(
      'product_id', v_product_id,
      'variant_id', v_variant_id,
      'variant_label', v_variant_label,
      'product_name', v_product.name,
      'quantity', v_quantity,
      'unit_price', v_unit_price,
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
      variant_id,
      variant_label,
      product_name,
      quantity,
      unit_price,
      product_currency,
      line_total
    )
    values (
      v_sale.id,
      (v_item->>'product_id')::uuid,
      nullif(v_item->>'variant_id', '')::uuid,
      nullif(v_item->>'variant_label', ''),
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
