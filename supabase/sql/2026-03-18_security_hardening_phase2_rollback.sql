-- Rollback for 2026-03-18_security_hardening_phase2.sql
-- Generated on 2026-03-18

BEGIN;

-- ---------------------------------------------------------------------------
-- Revert point 5 (onboarding hardening)
-- ---------------------------------------------------------------------------

-- Restore prior simpler onboarding RPC behavior.
CREATE OR REPLACE FUNCTION public.create_company_for_current_user(
  company_name text,
  company_email text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_company_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  INSERT INTO public.companies(name, email, subscription_status)
  VALUES (company_name, company_email, 'trial')
  RETURNING id INTO new_company_id;

  INSERT INTO public.users(id, email, company_id)
  VALUES (auth.uid(), company_email, new_company_id)
  ON CONFLICT (id)
  DO UPDATE SET
    email = EXCLUDED.email,
    company_id = EXCLUDED.company_id;

  RETURN new_company_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_company_for_current_user(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_company_for_current_user(text, text) TO authenticated;

DROP TABLE IF EXISTS public.company_creation_attempts;

-- ---------------------------------------------------------------------------
-- Revert point 4 (tenant integrity triggers)
-- ---------------------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_service_order_items_tenant_integrity ON public.service_order_items;
DROP TRIGGER IF EXISTS trg_service_orders_tenant_integrity ON public.service_orders;
DROP TRIGGER IF EXISTS trg_reservations_tenant_integrity ON public.reservations;
DROP TRIGGER IF EXISTS trg_categories_parent_company ON public.categories;

DROP FUNCTION IF EXISTS public.guard_service_order_items_tenant_integrity();
DROP FUNCTION IF EXISTS public.guard_service_orders_tenant_integrity();
DROP FUNCTION IF EXISTS public.guard_reservations_tenant_integrity();
DROP FUNCTION IF EXISTS public.guard_categories_parent_company();

-- ---------------------------------------------------------------------------
-- Revert point 3 (users direct insert policy)
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS users_insert_denied ON public.users;

CREATE POLICY users_insert_self
ON public.users
FOR INSERT
WITH CHECK (id = auth.uid());

-- ---------------------------------------------------------------------------
-- Revert point 2 (assign helper hardening)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.assign_user_to_company_by_email(
  p_email text,
  p_role public.app_role DEFAULT 'seller'::public.app_role
)
RETURNS public.users
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_company_id uuid;
  v_target_id uuid;
  v_target_email text;
  v_user public.users;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT public.is_manager() THEN
    RAISE EXCEPTION 'Manager role required';
  END IF;

  v_company_id := public.current_company_id();
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Company not found for current user';
  END IF;

  SELECT u.id, u.email
  INTO v_target_id, v_target_email
  FROM auth.users u
  WHERE lower(u.email) = lower(trim(p_email))
  LIMIT 1;

  IF v_target_id IS NULL THEN
    RAISE EXCEPTION 'Aucun compte trouve pour cet email. Le compte doit etre cree avant attribution.';
  END IF;

  INSERT INTO public.users(id, email, company_id, role)
  VALUES (v_target_id, COALESCE(v_target_email, trim(p_email)), v_company_id, p_role)
  ON CONFLICT (id)
  DO UPDATE
  SET
    email = EXCLUDED.email,
    company_id = EXCLUDED.company_id,
    role = EXCLUDED.role;

  SELECT u.*
  INTO v_user
  FROM public.users u
  WHERE u.id = v_target_id
  LIMIT 1;

  RETURN v_user;
END;
$$;

REVOKE ALL ON FUNCTION public.assign_user_to_company_by_email(text, public.app_role) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assign_user_to_company_by_email(text, public.app_role) TO authenticated;

-- ---------------------------------------------------------------------------
-- Revert point 1 (users update hardening)
-- ---------------------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_users_guard_sensitive_fields ON public.users;
DROP FUNCTION IF EXISTS public.guard_users_sensitive_fields();

DROP POLICY IF EXISTS users_update_self_safe ON public.users;
DROP POLICY IF EXISTS users_update_manager_company ON public.users;

CREATE POLICY users_update_self_or_manager_company
ON public.users
FOR UPDATE
USING (
  id = auth.uid()
  OR (
    company_id = public.current_company_id()
    AND public.is_manager()
  )
)
WITH CHECK (
  company_id = public.current_company_id()
);

COMMIT;
