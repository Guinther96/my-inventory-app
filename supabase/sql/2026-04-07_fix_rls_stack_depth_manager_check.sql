-- Fix: stack depth limit exceeded (PostgrestException code 54001)
-- Root cause: current_user_is_manager() queries public.users without SECURITY DEFINER.
-- When the users_select_own_company RLS policy evaluates current_user_is_manager(),
-- it re-queries public.users, which re-evaluates the same policy, causing infinite recursion.
-- Same risk exists for company_is_active() which queries public.companies (less critical
-- but fixed here defensively so it never triggers a chain through companies RLS either).
--
-- Pattern follows the existing fix in 2026-03-10_fix_rls_stack_depth.sql which applied
-- SECURITY DEFINER to current_company_id() for the same reason.

begin;

-- -------------------------------------------------------------------------
-- 1) current_user_is_manager() — add SECURITY DEFINER + fixed search_path
-- -------------------------------------------------------------------------
-- Without SECURITY DEFINER this function runs as the calling user and is
-- subject to RLS on public.users, causing recursive RLS evaluation.
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

-- -------------------------------------------------------------------------
-- 2) company_is_active() — add SECURITY DEFINER + fixed search_path
-- -------------------------------------------------------------------------
-- Queries public.companies; without SECURITY DEFINER it runs as calling user
-- and the companies_select_own policy calls current_company_id() again.
-- Making it SECURITY DEFINER removes any risk of chained policy recursion.
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
