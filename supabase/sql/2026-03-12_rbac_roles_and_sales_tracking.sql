-- RBAC migration (manager/seller) + seller tracking on sales-related tables.
-- Idempotent and safe for existing data.

-- 1) Role type and users.role column
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type WHERE typname = 'app_role'
  ) THEN
    CREATE TYPE public.app_role AS ENUM ('manager', 'seller');
  END IF;
END
$$;

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS role public.app_role;

UPDATE public.users
SET role = 'manager'::public.app_role
WHERE role IS NULL;

ALTER TABLE public.users
  ALTER COLUMN role SET DEFAULT 'manager'::public.app_role;

ALTER TABLE public.users
  ALTER COLUMN role SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_users_company_role
ON public.users(company_id, role);

-- 2) Security-definer helper to read current role safely (no recursive RLS).
CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS public.app_role
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (
      SELECT u.role
      FROM public.users u
      WHERE u.id = auth.uid()
      LIMIT 1
    ),
    'seller'::public.app_role
  );
$$;

REVOKE ALL ON FUNCTION public.current_user_role() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.current_user_role() TO authenticated;

CREATE OR REPLACE FUNCTION public.is_manager()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.current_user_role() = 'manager'::public.app_role;
$$;

REVOKE ALL ON FUNCTION public.is_manager() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_manager() TO authenticated;

-- 3) Optional seller tracking on sales table (if table exists)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'sales'
  ) THEN
    ALTER TABLE public.sales
      ADD COLUMN IF NOT EXISTS seller_id uuid;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_constraint
      WHERE conname = 'sales_seller_id_fkey'
        AND conrelid = 'public.sales'::regclass
    ) THEN
      ALTER TABLE public.sales
        ADD CONSTRAINT sales_seller_id_fkey
        FOREIGN KEY (seller_id)
        REFERENCES public.users(id)
        ON DELETE SET NULL;
    END IF;

    CREATE INDEX IF NOT EXISTS idx_sales_company_id
      ON public.sales(company_id);
    CREATE INDEX IF NOT EXISTS idx_sales_seller_id
      ON public.sales(seller_id);

    IF EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'sales'
        AND column_name = 'user_id'
    ) THEN
      EXECUTE '
        UPDATE public.sales
        SET seller_id = user_id
        WHERE seller_id IS NULL
          AND user_id IS NOT NULL
      ';
    END IF;

    UPDATE public.sales
    SET seller_id = auth.uid()
    WHERE seller_id IS NULL
      AND auth.uid() IS NOT NULL;
  END IF;
END
$$;

-- 4) Optional seller tracking on stock_movements for sales exits
ALTER TABLE public.stock_movements
  ADD COLUMN IF NOT EXISTS seller_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'stock_movements_seller_id_fkey'
      AND conrelid = 'public.stock_movements'::regclass
  ) THEN
    ALTER TABLE public.stock_movements
      ADD CONSTRAINT stock_movements_seller_id_fkey
      FOREIGN KEY (seller_id)
      REFERENCES public.users(id)
      ON DELETE SET NULL;
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_stock_movements_seller_id
ON public.stock_movements(seller_id);

UPDATE public.stock_movements
SET seller_id = user_id
WHERE seller_id IS NULL
  AND type = 'exit'
  AND user_id IS NOT NULL;

-- 5) RLS policies by role
-- users
DROP POLICY IF EXISTS users_select_self ON public.users;
DROP POLICY IF EXISTS users_select_self_or_manager_company ON public.users;
CREATE POLICY users_select_self_or_manager_company
ON public.users
FOR SELECT
USING (
  id = auth.uid()
  OR (
    company_id = public.current_company_id()
    AND public.is_manager()
  )
);

DROP POLICY IF EXISTS users_insert_self ON public.users;
CREATE POLICY users_insert_self
ON public.users
FOR INSERT
WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS users_update_self ON public.users;
DROP POLICY IF EXISTS users_update_self_or_manager_company ON public.users;
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

-- categories
DROP POLICY IF EXISTS categories_select_company ON public.categories;
CREATE POLICY categories_select_company
ON public.categories
FOR SELECT
USING (company_id = public.current_company_id());

DROP POLICY IF EXISTS categories_insert_company ON public.categories;
DROP POLICY IF EXISTS categories_insert_manager ON public.categories;
CREATE POLICY categories_insert_manager
ON public.categories
FOR INSERT
WITH CHECK (
  company_id = public.current_company_id()
  AND public.is_manager()
);

DROP POLICY IF EXISTS categories_update_company ON public.categories;
DROP POLICY IF EXISTS categories_update_manager ON public.categories;
CREATE POLICY categories_update_manager
ON public.categories
FOR UPDATE
USING (
  company_id = public.current_company_id()
  AND public.is_manager()
)
WITH CHECK (
  company_id = public.current_company_id()
  AND public.is_manager()
);

DROP POLICY IF EXISTS categories_delete_company ON public.categories;
DROP POLICY IF EXISTS categories_delete_manager ON public.categories;
CREATE POLICY categories_delete_manager
ON public.categories
FOR DELETE
USING (
  company_id = public.current_company_id()
  AND public.is_manager()
);

-- products
DROP POLICY IF EXISTS products_select_company ON public.products;
CREATE POLICY products_select_company
ON public.products
FOR SELECT
USING (company_id = public.current_company_id());

DROP POLICY IF EXISTS products_insert_company ON public.products;
DROP POLICY IF EXISTS products_insert_manager ON public.products;
CREATE POLICY products_insert_manager
ON public.products
FOR INSERT
WITH CHECK (
  company_id = public.current_company_id()
  AND public.is_manager()
);

DROP POLICY IF EXISTS products_update_company ON public.products;
DROP POLICY IF EXISTS products_update_manager ON public.products;
CREATE POLICY products_update_manager
ON public.products
FOR UPDATE
USING (
  company_id = public.current_company_id()
  AND public.is_manager()
)
WITH CHECK (
  company_id = public.current_company_id()
  AND public.is_manager()
);

DROP POLICY IF EXISTS products_delete_company ON public.products;
DROP POLICY IF EXISTS products_delete_manager ON public.products;
CREATE POLICY products_delete_manager
ON public.products
FOR DELETE
USING (
  company_id = public.current_company_id()
  AND public.is_manager()
);

-- stock_movements
DROP POLICY IF EXISTS movements_select_company ON public.stock_movements;
CREATE POLICY movements_select_company
ON public.stock_movements
FOR SELECT
USING (company_id = public.current_company_id());

DROP POLICY IF EXISTS movements_insert_company ON public.stock_movements;
DROP POLICY IF EXISTS movements_insert_manager_or_seller_exit ON public.stock_movements;
CREATE POLICY movements_insert_manager_or_seller_exit
ON public.stock_movements
FOR INSERT
WITH CHECK (
  company_id = public.current_company_id()
  AND (
    -- Managers can insert any movement type.
    (
      public.is_manager()
      AND (
        user_id IS NULL
        OR EXISTS (
          SELECT 1
          FROM public.users u
          WHERE u.id = user_id
            AND u.company_id = public.current_company_id()
        )
      )
    )
    OR
    -- Sellers can only create sales exits attributed to themselves.
    (
      NOT public.is_manager()
      AND type = 'exit'
      AND COALESCE(user_id, auth.uid()) = auth.uid()
      AND COALESCE(seller_id, auth.uid()) = auth.uid()
    )
  )
);

DROP POLICY IF EXISTS movements_update_company ON public.stock_movements;
DROP POLICY IF EXISTS movements_update_manager ON public.stock_movements;
CREATE POLICY movements_update_manager
ON public.stock_movements
FOR UPDATE
USING (
  company_id = public.current_company_id()
  AND public.is_manager()
)
WITH CHECK (
  company_id = public.current_company_id()
  AND public.is_manager()
);

DROP POLICY IF EXISTS movements_delete_company ON public.stock_movements;
DROP POLICY IF EXISTS movements_delete_manager ON public.stock_movements;
CREATE POLICY movements_delete_manager
ON public.stock_movements
FOR DELETE
USING (
  company_id = public.current_company_id()
  AND public.is_manager()
);

-- sales and sale_items (apply only if tables exist)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'sales'
  ) THEN
    EXECUTE 'ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY';

    EXECUTE 'DROP POLICY IF EXISTS sales_select_company_role ON public.sales';
    EXECUTE '
      CREATE POLICY sales_select_company_role
      ON public.sales
      FOR SELECT
      USING (
        company_id = public.current_company_id()
        AND (
          public.is_manager()
          OR seller_id = auth.uid()
        )
      )
    ';

    EXECUTE 'DROP POLICY IF EXISTS sales_insert_company_role ON public.sales';
    EXECUTE '
      CREATE POLICY sales_insert_company_role
      ON public.sales
      FOR INSERT
      WITH CHECK (
        company_id = public.current_company_id()
        AND (
          public.is_manager()
          OR COALESCE(seller_id, auth.uid()) = auth.uid()
        )
      )
    ';

    EXECUTE 'DROP POLICY IF EXISTS sales_update_manager_only ON public.sales';
    EXECUTE '
      CREATE POLICY sales_update_manager_only
      ON public.sales
      FOR UPDATE
      USING (
        company_id = public.current_company_id()
        AND public.is_manager()
      )
      WITH CHECK (
        company_id = public.current_company_id()
        AND public.is_manager()
      )
    ';

    EXECUTE 'DROP POLICY IF EXISTS sales_delete_manager_only ON public.sales';
    EXECUTE '
      CREATE POLICY sales_delete_manager_only
      ON public.sales
      FOR DELETE
      USING (
        company_id = public.current_company_id()
        AND public.is_manager()
      )
    ';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'sale_items'
  ) AND EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'sales'
  ) THEN
    EXECUTE 'ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY';

    EXECUTE 'DROP POLICY IF EXISTS sale_items_select_company_role ON public.sale_items';
    EXECUTE '
      CREATE POLICY sale_items_select_company_role
      ON public.sale_items
      FOR SELECT
      USING (
        EXISTS (
          SELECT 1
          FROM public.sales s
          WHERE s.id = sale_items.sale_id
            AND s.company_id = public.current_company_id()
            AND (
              public.is_manager()
              OR s.seller_id = auth.uid()
            )
        )
      )
    ';

    EXECUTE 'DROP POLICY IF EXISTS sale_items_insert_company_role ON public.sale_items';
    EXECUTE '
      CREATE POLICY sale_items_insert_company_role
      ON public.sale_items
      FOR INSERT
      WITH CHECK (
        EXISTS (
          SELECT 1
          FROM public.sales s
          WHERE s.id = sale_items.sale_id
            AND s.company_id = public.current_company_id()
            AND (
              public.is_manager()
              OR s.seller_id = auth.uid()
            )
        )
      )
    ';

    EXECUTE 'DROP POLICY IF EXISTS sale_items_update_manager_only ON public.sale_items';
    EXECUTE '
      CREATE POLICY sale_items_update_manager_only
      ON public.sale_items
      FOR UPDATE
      USING (
        EXISTS (
          SELECT 1
          FROM public.sales s
          WHERE s.id = sale_items.sale_id
            AND s.company_id = public.current_company_id()
            AND public.is_manager()
        )
      )
      WITH CHECK (
        EXISTS (
          SELECT 1
          FROM public.sales s
          WHERE s.id = sale_items.sale_id
            AND s.company_id = public.current_company_id()
            AND public.is_manager()
        )
      )
    ';

    EXECUTE 'DROP POLICY IF EXISTS sale_items_delete_manager_only ON public.sale_items';
    EXECUTE '
      CREATE POLICY sale_items_delete_manager_only
      ON public.sale_items
      FOR DELETE
      USING (
        EXISTS (
          SELECT 1
          FROM public.sales s
          WHERE s.id = sale_items.sale_id
            AND s.company_id = public.current_company_id()
            AND public.is_manager()
        )
      )
    ';
  END IF;
END
$$;
