begin;

-- Deduplicate products by business key per company.
-- Business key priority:
-- 1) non-empty barcode (normalized)
-- 2) normalized name when barcode is empty
-- Keep the most recently updated row and remove the others.

with ranked_products as (
  select
    p.id,
    p.company_id,
    coalesce(
      nullif(lower(btrim(p.barcode)), ''),
      'name:' || lower(btrim(p.name))
    ) as business_key,
    row_number() over (
      partition by
        p.company_id,
        coalesce(
          nullif(lower(btrim(p.barcode)), ''),
          'name:' || lower(btrim(p.name))
        )
      order by p.updated_at desc nulls last, p.created_at desc nulls last, p.id desc
    ) as rn
  from public.products p
),
keepers as (
  select company_id, business_key, id as keep_id
  from ranked_products
  where rn = 1
),
duplicates as (
  select rp.id as duplicate_id, k.keep_id
  from ranked_products rp
  join keepers k
    on k.company_id = rp.company_id
   and k.business_key = rp.business_key
  where rp.rn > 1
)
update public.stock_movements sm
set product_id = d.keep_id
from duplicates d
where sm.product_id = d.duplicate_id;

with ranked_products as (
  select
    p.id,
    p.company_id,
    coalesce(
      nullif(lower(btrim(p.barcode)), ''),
      'name:' || lower(btrim(p.name))
    ) as business_key,
    row_number() over (
      partition by
        p.company_id,
        coalesce(
          nullif(lower(btrim(p.barcode)), ''),
          'name:' || lower(btrim(p.name))
        )
      order by p.updated_at desc nulls last, p.created_at desc nulls last, p.id desc
    ) as rn
  from public.products p
)
delete from public.products p
using ranked_products rp
where p.id = rp.id
  and rp.rn > 1;

create unique index if not exists idx_products_company_name_normalized_unique
on public.products (company_id, lower(btrim(name)));

create unique index if not exists idx_products_company_barcode_normalized_unique
on public.products (company_id, lower(btrim(barcode)))
where barcode is not null and btrim(barcode) <> '';

commit;
