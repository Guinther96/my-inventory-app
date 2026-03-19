-- Allow seller checkout to update stock safely via SECURITY DEFINER RPC.
-- This keeps products UPDATE locked to managers at policy level,
-- while permitting controlled sale exits for sellers.

CREATE OR REPLACE FUNCTION public.process_sale_exit(
  p_company_id uuid,
  p_product_id uuid,
  p_quantity integer,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid;
  v_user_company uuid;
  v_product public.products%ROWTYPE;
  v_updated_product public.products%ROWTYPE;
  v_movement public.stock_movements%ROWTYPE;
  v_next_qty integer;
BEGIN
  v_uid := auth.uid();

  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Quantity must be greater than zero';
  END IF;

  SELECT u.company_id
  INTO v_user_company
  FROM public.users u
  WHERE u.id = v_uid
  LIMIT 1;

  IF v_user_company IS NULL OR v_user_company <> p_company_id THEN
    RAISE EXCEPTION 'Unauthorized company context';
  END IF;

  SELECT *
  INTO v_product
  FROM public.products p
  WHERE p.id = p_product_id
    AND p.company_id = p_company_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Product not found in company';
  END IF;

  v_next_qty := COALESCE(v_product.quantity, 0) - p_quantity;
  IF v_next_qty < 0 THEN
    v_next_qty := 0;
  END IF;

  UPDATE public.products p
  SET quantity = v_next_qty,
      updated_at = now()
  WHERE p.id = p_product_id
    AND p.company_id = p_company_id
  RETURNING * INTO v_updated_product;

  INSERT INTO public.stock_movements (
    product_id,
    user_id,
    seller_id,
    type,
    quantity,
    notes,
    company_id
  )
  VALUES (
    p_product_id,
    v_uid,
    v_uid,
    'exit',
    p_quantity,
    NULLIF(BTRIM(COALESCE(p_notes, '')), ''),
    p_company_id
  )
  RETURNING * INTO v_movement;

  RETURN jsonb_build_object(
    'product', to_jsonb(v_updated_product),
    'movement', to_jsonb(v_movement)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.process_sale_exit(uuid, uuid, integer, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.process_sale_exit(uuid, uuid, integer, text) TO authenticated;
