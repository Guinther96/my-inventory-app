begin;

-- 1) Restore the users select policy to the version used by the main app migration.
drop policy if exists users_select_own_company on public.users;
create policy users_select_own_company
on public.users
for select
using (
  company_id = public.current_company_id()
  and public.current_company_is_active()
  and (public.current_user_is_manager() or id = auth.uid())
);

-- 2) Safety: keep trigger function available (no behavior change here).
create or replace function public.ensure_public_user_for_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  insert into public.users(id, email, company_id, role)
  values (
    new.id,
    coalesce(new.email, ''),
    null,
    'seller'::public.app_role
  )
  on conflict (id)
  do update set
    email = excluded.email;

  return new;
end;
$$;

commit;
