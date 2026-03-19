-- Fix stack depth exceeded caused by recursive RLS evaluation.
-- Root cause: users select policy depended on current_company_id(), while
-- current_company_id() queried public.users, which re-triggered users RLS.

create or replace function public.current_company_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select u.company_id
  from public.users u
  where u.id = auth.uid()
  limit 1;
$$;

revoke all on function public.current_company_id() from public;
grant execute on function public.current_company_id() to authenticated;

-- Keep users table policies non-recursive.
drop policy if exists users_select_own_company on public.users;
create policy users_select_self
on public.users
for select
using (id = auth.uid());

-- Ensure expected self-service policies are still present.
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
