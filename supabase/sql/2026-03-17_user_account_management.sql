-- Manager account management helpers:
-- - attach an existing auth account to manager company with role manager/seller
-- - remove seller accounts from manager company

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

CREATE OR REPLACE FUNCTION public.remove_seller_from_company(
  p_user_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_rows integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT public.is_manager() THEN
    RAISE EXCEPTION 'Manager role required';
  END IF;

  IF p_user_id = auth.uid() THEN
    RAISE EXCEPTION 'Vous ne pouvez pas supprimer votre propre compte.';
  END IF;

  v_company_id := public.current_company_id();
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Company not found for current user';
  END IF;

  DELETE FROM public.users
  WHERE id = p_user_id
    AND company_id = v_company_id
    AND role = 'seller'::public.app_role;

  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows = 0 THEN
    RAISE EXCEPTION 'Suppression impossible: seul un seller de votre compagnie peut etre supprime.';
  END IF;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.remove_seller_from_company(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.remove_seller_from_company(uuid) TO authenticated;
