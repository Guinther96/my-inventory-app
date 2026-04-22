-- Hotfix runtime for PostgrestException 54001 (stack depth limit exceeded)
-- Safe and idempotent: can be executed multiple times.
--
-- What it does:
-- 1) Enforces SECURITY DEFINER + fixed search_path on helper functions
--    used by RLS checks.
-- 2) Restores execute grants for authenticated role.
-- 3) Prints verification rows at the end.

begin;

create or replace function public.current_user_is_manager()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.role = 'manager'::public.app_role
  );
$$;

revoke all on function public.current_user_is_manager() from public;
grant execute on function public.current_user_is_manager() to authenticated;

create or replace function public.company_is_active(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.companies c
    where c.id = p_company_id
      and public.normalize_company_status(c.status) = 'active'
  );
$$;

revoke all on function public.company_is_active(uuid) from public;
grant execute on function public.company_is_active(uuid) to authenticated;

commit;

-- Verification block
select
  n.nspname as schema_name,
  p.proname as function_name,
  p.prosecdef as security_definer,
  p.provolatile as volatility,
  pg_get_userbyid(p.proowner) as owner_name,
  pg_get_functiondef(p.oid) as function_ddl
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('current_user_is_manager', 'company_is_active')
order by p.proname;

select
  p.proname as function_name,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_can_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('current_user_is_manager', 'company_is_active')
order by p.proname;
