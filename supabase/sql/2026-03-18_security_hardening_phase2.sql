-- Security hardening phase 2 (multi-tenant + RBAC)
-- Generated on 2026-03-18
--
-- Covers:
-- 1) Prevent seller privilege escalation on users updates
-- 2) Block cross-tenant account takeover in assign_user_to_company_by_email
-- 3) Block direct INSERT into public.users from client role
-- 4) Enforce tenant integrity across cross-table references
-- 5) Harden create_company_for_current_user (idempotent + basic throttling)
-- 6) Auth dashboard hardening checklist (manual, documented at bottom)

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) USERS UPDATE HARDENING
-- ---------------------------------------------------------------------------

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS users_update_self ON public.users;
DROP POLICY IF EXISTS users_update_self_or_manager_company ON public.users;
DROP POLICY IF EXISTS users_update_manager_company ON public.users;

-- Self updates are allowed only on own row and same company context.
CREATE POLICY users_update_self_safe
ON public.users
FOR UPDATE
USING (
  id = auth.uid()
)
WITH CHECK (
  id = auth.uid()
  AND company_id = public.current_company_id()
);

-- Managers can update users in their own company.
CREATE POLICY users_update_manager_company
ON public.users
FOR UPDATE
USING (
  company_id = public.current_company_id()
  AND public.is_manager()
)
WITH CHECK (
  company_id = public.current_company_id()
  AND public.is_manager()
);

-- Extra guardrail: non-managers cannot change role/company_id even on their own row.
CREATE OR REPLACE FUNCTION public.guard_users_sensitive_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $guard_users$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF auth.uid() IS NULL THEN
      RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF NOT public.is_manager() THEN
      IF NEW.company_id IS DISTINCT FROM OLD.company_id THEN
        RAISE EXCEPTION 'Changing company_id is not allowed';
      END IF;

      IF NEW.role IS DISTINCT FROM OLD.role THEN
        RAISE EXCEPTION 'Changing role is not allowed';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$guard_users$;

REVOKE ALL ON FUNCTION public.guard_users_sensitive_fields() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.guard_users_sensitive_fields() TO authenticated;

DROP TRIGGER IF EXISTS trg_users_guard_sensitive_fields ON public.users;
CREATE TRIGGER trg_users_guard_sensitive_fields
BEFORE UPDATE ON public.users
FOR EACH ROW
EXECUTE FUNCTION public.guard_users_sensitive_fields();

-- ---------------------------------------------------------------------------
-- 2) ACCOUNT ASSIGNMENT HARDENING (NO CROSS-TENANT TAKEOVER)
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.assign_user_to_company_by_email(text, public.app_role);

CREATE OR REPLACE FUNCTION public.assign_user_to_company_by_email(
  p_email text,
  p_role public.app_role DEFAULT 'seller'::public.app_role
)
RETURNS public.users
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $assign_user$
DECLARE
  v_company_id uuid;
  v_target_id uuid;
  v_target_email text;
  v_existing_company_id uuid;
  v_existing_role public.app_role;
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

  SELECT u.company_id, u.role
  INTO v_existing_company_id, v_existing_role
  FROM public.users u
  WHERE u.id = v_target_id
  LIMIT 1;

  -- Prevent moving an already linked account from another company.
  IF v_existing_company_id IS NOT NULL AND v_existing_company_id <> v_company_id THEN
    RAISE EXCEPTION 'Ce compte est deja rattache a une autre compagnie.';
  END IF;

  -- Avoid accidental manager downgrade through this helper.
  IF v_existing_role = 'manager'::public.app_role
     AND p_role <> 'manager'::public.app_role THEN
    RAISE EXCEPTION 'Impossible de retrograder un manager avec cette operation.';
  END IF;

  INSERT INTO public.users(id, email, company_id, role)
  VALUES (v_target_id, COALESCE(v_target_email, trim(p_email)), v_company_id, p_role)
  ON CONFLICT (id)
  DO UPDATE
  SET
    email = EXCLUDED.email,
    role = EXCLUDED.role
  WHERE public.users.company_id = v_company_id;

  SELECT u.*
  INTO v_user
  FROM public.users u
  WHERE u.id = v_target_id
  LIMIT 1;

  IF v_user.id IS NULL OR v_user.company_id <> v_company_id THEN
    RAISE EXCEPTION 'Attribution refusee: compte non modifiable hors compagnie.';
  END IF;

  RETURN v_user;
END;
$assign_user$;

REVOKE ALL ON FUNCTION public.assign_user_to_company_by_email(text, public.app_role) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assign_user_to_company_by_email(text, public.app_role) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3) BLOCK DIRECT INSERT INTO public.users FROM CLIENT
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS users_insert_self ON public.users;
DROP POLICY IF EXISTS users_insert_denied ON public.users;

CREATE POLICY users_insert_denied
ON public.users
FOR INSERT
WITH CHECK (false);

-- ---------------------------------------------------------------------------
-- 4) TENANT INTEGRITY GUARDS (CROSS-TABLE COMPANY CONSISTENCY)
-- ---------------------------------------------------------------------------

-- 4.1 categories.parent_id must stay in same company.
CREATE OR REPLACE FUNCTION public.guard_categories_parent_company()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $guard_cat_parent$
DECLARE
  v_parent_company uuid;
BEGIN
  IF NEW.parent_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT c.company_id
  INTO v_parent_company
  FROM public.categories c
  WHERE c.id = NEW.parent_id;

  IF v_parent_company IS NULL THEN
    RAISE EXCEPTION 'Parent category not found';
  END IF;

  IF v_parent_company <> NEW.company_id THEN
    RAISE EXCEPTION 'Parent category must belong to the same company';
  END IF;

  RETURN NEW;
END;
$guard_cat_parent$;

DROP TRIGGER IF EXISTS trg_categories_parent_company ON public.categories;
CREATE TRIGGER trg_categories_parent_company
BEFORE INSERT OR UPDATE ON public.categories
FOR EACH ROW
EXECUTE FUNCTION public.guard_categories_parent_company();

-- 4.2 reservations references (client/service/converted order) must match reservation company.
CREATE OR REPLACE FUNCTION public.guard_reservations_tenant_integrity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $guard_res$
DECLARE
  v_client_company uuid;
  v_service_company uuid;
  v_order_company uuid;
BEGIN
  IF NEW.client_id IS NOT NULL THEN
    SELECT c.company_id
    INTO v_client_company
    FROM public.clients c
    WHERE c.id = NEW.client_id;

    IF v_client_company IS NULL OR v_client_company <> NEW.company_id THEN
      RAISE EXCEPTION 'Reservation client must belong to the same company';
    END IF;
  END IF;

  IF NEW.service_id IS NOT NULL THEN
    SELECT s.company_id
    INTO v_service_company
    FROM public.services s
    WHERE s.id = NEW.service_id;

    IF v_service_company IS NULL OR v_service_company <> NEW.company_id THEN
      RAISE EXCEPTION 'Reservation service must belong to the same company';
    END IF;
  END IF;

  IF NEW.converted_order_id IS NOT NULL THEN
    SELECT so.company_id
    INTO v_order_company
    FROM public.service_orders so
    WHERE so.id = NEW.converted_order_id;

    IF v_order_company IS NULL OR v_order_company <> NEW.company_id THEN
      RAISE EXCEPTION 'Converted order must belong to the same company';
    END IF;
  END IF;

  RETURN NEW;
END;
$guard_res$;

DROP TRIGGER IF EXISTS trg_reservations_tenant_integrity ON public.reservations;
CREATE TRIGGER trg_reservations_tenant_integrity
BEFORE INSERT OR UPDATE ON public.reservations
FOR EACH ROW
EXECUTE FUNCTION public.guard_reservations_tenant_integrity();

-- 4.3 service_orders references (client/reservation) must match order company.
CREATE OR REPLACE FUNCTION public.guard_service_orders_tenant_integrity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $guard_orders$
DECLARE
  v_client_company uuid;
  v_reservation_company uuid;
BEGIN
  IF NEW.client_id IS NOT NULL THEN
    SELECT c.company_id
    INTO v_client_company
    FROM public.clients c
    WHERE c.id = NEW.client_id;

    IF v_client_company IS NULL OR v_client_company <> NEW.company_id THEN
      RAISE EXCEPTION 'Order client must belong to the same company';
    END IF;
  END IF;

  IF NEW.reservation_id IS NOT NULL THEN
    SELECT r.company_id
    INTO v_reservation_company
    FROM public.reservations r
    WHERE r.id = NEW.reservation_id;

    IF v_reservation_company IS NULL OR v_reservation_company <> NEW.company_id THEN
      RAISE EXCEPTION 'Order reservation must belong to the same company';
    END IF;
  END IF;

  RETURN NEW;
END;
$guard_orders$;

DROP TRIGGER IF EXISTS trg_service_orders_tenant_integrity ON public.service_orders;
CREATE TRIGGER trg_service_orders_tenant_integrity
BEFORE INSERT OR UPDATE ON public.service_orders
FOR EACH ROW
EXECUTE FUNCTION public.guard_service_orders_tenant_integrity();

-- 4.4 service_order_items.service_id must belong to same company as parent service_order.
CREATE OR REPLACE FUNCTION public.guard_service_order_items_tenant_integrity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $guard_order_items$
DECLARE
  v_order_company uuid;
  v_service_company uuid;
BEGIN
  SELECT so.company_id
  INTO v_order_company
  FROM public.service_orders so
  WHERE so.id = NEW.service_order_id;

  IF v_order_company IS NULL THEN
    RAISE EXCEPTION 'Parent service order not found';
  END IF;

  IF NEW.service_id IS NOT NULL THEN
    SELECT s.company_id
    INTO v_service_company
    FROM public.services s
    WHERE s.id = NEW.service_id;

    IF v_service_company IS NULL THEN
      RAISE EXCEPTION 'Service not found';
    END IF;

    IF v_service_company <> v_order_company THEN
      RAISE EXCEPTION 'Order item service must belong to the same company as the order';
    END IF;
  END IF;

  RETURN NEW;
END;
$guard_order_items$;

DROP TRIGGER IF EXISTS trg_service_order_items_tenant_integrity ON public.service_order_items;
CREATE TRIGGER trg_service_order_items_tenant_integrity
BEFORE INSERT OR UPDATE ON public.service_order_items
FOR EACH ROW
EXECUTE FUNCTION public.guard_service_order_items_tenant_integrity();

-- ---------------------------------------------------------------------------
-- 5) ONBOARDING HARDENING: create_company_for_current_user
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.company_creation_attempts (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  last_attempt_at timestamptz NOT NULL DEFAULT now()
);

DROP FUNCTION IF EXISTS public.create_company_for_current_user(text, text);

CREATE OR REPLACE FUNCTION public.create_company_for_current_user(
  company_name text,
  company_email text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $create_company$
DECLARE
  v_uid uuid;
  v_existing_company_id uuid;
  v_last_attempt_at timestamptz;
  v_new_company_id uuid;
  v_clean_name text;
  v_clean_email text;
BEGIN
  v_uid := auth.uid();

  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Idempotent behavior: if already linked to a company, return it.
  SELECT u.company_id
  INTO v_existing_company_id
  FROM public.users u
  WHERE u.id = v_uid
  LIMIT 1;

  IF v_existing_company_id IS NOT NULL THEN
    RETURN v_existing_company_id;
  END IF;

  -- Basic anti-spam throttle per user.
  SELECT a.last_attempt_at
  INTO v_last_attempt_at
  FROM public.company_creation_attempts a
  WHERE a.user_id = v_uid
  LIMIT 1;

  IF v_last_attempt_at IS NOT NULL
     AND now() - v_last_attempt_at < interval '30 seconds' THEN
    RAISE EXCEPTION 'Too many onboarding attempts. Please retry in a few seconds.';
  END IF;

  INSERT INTO public.company_creation_attempts(user_id, last_attempt_at)
  VALUES (v_uid, now())
  ON CONFLICT (user_id)
  DO UPDATE
  SET last_attempt_at = EXCLUDED.last_attempt_at;

  v_clean_name := NULLIF(BTRIM(COALESCE(company_name, '')), '');
  v_clean_email := NULLIF(lower(BTRIM(COALESCE(company_email, ''))), '');

  IF v_clean_name IS NULL THEN
    RAISE EXCEPTION 'Company name is required';
  END IF;

  IF v_clean_email IS NULL THEN
    SELECT lower(au.email)
    INTO v_clean_email
    FROM auth.users au
    WHERE au.id = v_uid
    LIMIT 1;
  END IF;

  IF v_clean_email IS NULL THEN
    RAISE EXCEPTION 'Company email is required';
  END IF;

  INSERT INTO public.companies(name, email, subscription_status)
  VALUES (v_clean_name, v_clean_email, 'trial')
  RETURNING id INTO v_new_company_id;

  INSERT INTO public.users(id, email, company_id, role)
  VALUES (v_uid, v_clean_email, v_new_company_id, 'manager'::public.app_role)
  ON CONFLICT (id)
  DO UPDATE
  SET
    email = EXCLUDED.email,
    company_id = EXCLUDED.company_id,
    role = 'manager'::public.app_role;

  RETURN v_new_company_id;
END;
$create_company$;

REVOKE ALL ON FUNCTION public.create_company_for_current_user(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_company_for_current_user(text, text) TO authenticated;

COMMIT;

-- ---------------------------------------------------------------------------
-- 6) SUPABASE AUTH DASHBOARD HARDENING (MANUAL CHECKLIST)
-- ---------------------------------------------------------------------------
-- Run these in Supabase Dashboard > Authentication settings:
-- - Enable email confirmation (Confirm email = ON).
-- - Enable leaked password protection (if available on your plan/region).
-- - Tighten rate limits for sign-in, sign-up and password reset.
-- - Set a strict OTP expiry window.
-- - Disable public sign-up if you move to manager-invite only onboarding.
-- - Restrict allowed redirect URLs to your exact app domains.
