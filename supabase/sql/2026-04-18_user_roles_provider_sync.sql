begin;

-- Ensure provider role exists in app_role enum.
do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_enum e on e.enumtypid = t.oid
    where t.typname = 'app_role'
      and e.enumlabel = 'provider'
  ) then
    alter type public.app_role add value 'provider';
  end if;
end
$$;

-- Include provider accounts in auth -> public.users auto-sync.
create or replace function public.ensure_public_user_for_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_account_type text;
  v_target_role public.app_role;
begin
  v_account_type := lower(coalesce(new.raw_user_meta_data ->> 'account_type', ''));

  if v_account_type not in ('staff', 'company_owner', 'provider') then
    return new;
  end if;

  v_target_role := case
    when v_account_type = 'provider' then 'provider'::public.app_role
    else 'seller'::public.app_role
  end;

  insert into public.users(id, email, company_id, role)
  values (
    new.id,
    coalesce(new.email, ''),
    null,
    v_target_role
  )
  on conflict (id)
  do update set
    email = coalesce(excluded.email, public.users.email),
    role = excluded.role;

  return new;
end;
$$;

-- Generic removal helper for seller/provider accounts within manager company.
create or replace function public.remove_user_from_company(
  p_user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_rows integer;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not public.is_manager() then
    raise exception 'Manager role required';
  end if;

  if p_user_id = auth.uid() then
    raise exception 'Vous ne pouvez pas supprimer votre propre compte.';
  end if;

  v_company_id := public.current_company_id();
  if v_company_id is null then
    raise exception 'Company not found for current user';
  end if;

  delete from public.users
  where id = p_user_id
    and company_id = v_company_id
    and role in ('seller'::public.app_role, 'provider'::public.app_role);

  get diagnostics v_rows = row_count;

  if v_rows = 0 then
    raise exception 'Suppression impossible: seul un seller/prestataire de votre compagnie peut etre supprime.';
  end if;

  return true;
end;
$$;

revoke all on function public.remove_user_from_company(uuid) from public;
grant execute on function public.remove_user_from_company(uuid) to authenticated;

commit;
