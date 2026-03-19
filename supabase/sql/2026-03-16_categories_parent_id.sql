-- Add parent-child hierarchy for product categories.
-- A category can optionally reference another category in the same table.

ALTER TABLE public.categories
  ADD COLUMN IF NOT EXISTS parent_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'categories_parent_id_fkey'
      AND conrelid = 'public.categories'::regclass
  ) THEN
    ALTER TABLE public.categories
      ADD CONSTRAINT categories_parent_id_fkey
      FOREIGN KEY (parent_id)
      REFERENCES public.categories(id)
      ON DELETE SET NULL;
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'categories_parent_not_self'
      AND conrelid = 'public.categories'::regclass
  ) THEN
    ALTER TABLE public.categories
      ADD CONSTRAINT categories_parent_not_self
      CHECK (parent_id IS NULL OR parent_id <> id);
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_categories_parent_id
ON public.categories(parent_id);
