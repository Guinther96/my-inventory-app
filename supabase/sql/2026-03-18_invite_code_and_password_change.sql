-- Invite code + forced password change on first login.
-- Generated on 2026-03-18
--
-- Flow:
--   1) Manager creates staff account → app generates a random 8-char code
--      displayed in the UI (manager shares it with the employee).
--   2) Employee logs in with email + code (= temporary password).
--   3) App detects must_change_password = true → redirects to /change-password.
--   4) Employee sets a new password → flag cleared → normal access.

BEGIN;

-- Track whether the user must change their password on next login.
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS must_change_password boolean NOT NULL DEFAULT false;

-- Secure RPC: mark the current user as no longer needing password change.
-- Called by the app after the user successfully changes their password.
CREATE OR REPLACE FUNCTION public.clear_must_change_password()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $clear_pwd$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  UPDATE public.users
  SET must_change_password = false
  WHERE id = auth.uid();
END;
$clear_pwd$;

REVOKE ALL ON FUNCTION public.clear_must_change_password() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.clear_must_change_password() TO authenticated;

-- Secure RPC: manager sets must_change_password = true on a user in their company.
-- Called when creating a staff account with a temporary password/code.
-- Accepts email to avoid exposing internal UUIDs to the Flutter client.
CREATE OR REPLACE FUNCTION public.set_must_change_password(p_email text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $set_pwd$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT public.is_manager() THEN
    RAISE EXCEPTION 'Manager role required';
  END IF;

  UPDATE public.users
  SET must_change_password = true
  WHERE lower(email) = lower(p_email)
    AND company_id = public.current_company_id();
END;
$set_pwd$;

REVOKE ALL ON FUNCTION public.set_must_change_password(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_must_change_password(text) TO authenticated;

COMMIT;
