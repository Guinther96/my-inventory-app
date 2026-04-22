begin;

-- ---------------------------------------------------------------------------
-- Goal
-- ---------------------------------------------------------------------------
-- Keep email-confirmed users visible in public.users before company assignment,
-- without breaking other applications connected to the same Supabase project.
--
-- Compatibility rule:
-- Only sync auth users explicitly created for this app flow
-- (account_type in raw_user_meta_data: 'staff' or 'company_owner').

-- ---------------------------------------------------------------------------
-- 1) Schema compatibility
-- ---------------------------------------------------------------------------
alter table if exists public.users
  alter column company_id drop not null;

-- ---------------------------------------------------------------------------
-- 2) Trigger function (admin-safe)
-- ---------------------------------------------------------------------------
create or replace function public.ensure_public_user_for_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_account_type text;
begin
  v_account_type := lower(coalesce(new.raw_user_meta_data ->> 'account_type', ''));

  -- Ignore accounts that do not belong to this app onboarding flow.
  if v_account_type not in ('staff', 'company_owner') then
    return new;
  end if;

  insert into public.users(id, email, company_id, role)
  values (
    new.id,
    coalesce(new.email, ''),
    null,
    'seller'::public.app_role
  )
  on conflict (id)
  do update set
    email = coalesce(excluded.email, public.users.email);

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3) Trigger wiring
-- ---------------------------------------------------------------------------
drop trigger if exists trg_auth_user_autocreate_public_user on auth.users;
create trigger trg_auth_user_autocreate_public_user
after insert on auth.users
for each row
execute function public.ensure_public_user_for_auth_user();

-- ---------------------------------------------------------------------------
-- 4) Backfill (admin-safe)
-- ---------------------------------------------------------------------------
insert into public.users(id, email, company_id, role)
select
  au.id,
  coalesce(au.email, ''),
  null,
  'seller'::public.app_role
from auth.users au
left join public.users u on u.id = au.id
where u.id is null
  and lower(coalesce(au.raw_user_meta_data ->> 'account_type', '')) in (
    'staff',
    'company_owner'
  );

-- ---------------------------------------------------------------------------
-- IMPORTANT
-- ---------------------------------------------------------------------------
-- Do not alter existing RLS policies in this migration.
-- Policy changes must be handled in dedicated, reviewed migrations.

commit;
