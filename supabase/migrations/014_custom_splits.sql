-- ============================================
-- 014: Add Custom Split Participants Column
-- ============================================
-- This migration adds support for custom expense splits
-- where users can select specific participants.

-- 1. Drop the old scope check constraint that only allows global/sub_group
ALTER TABLE public.expenses DROP CONSTRAINT IF EXISTS expenses_scope_check;

-- 2. Add new constraint that includes all four scope values
ALTER TABLE public.expenses ADD CONSTRAINT expenses_scope_check 
  CHECK (scope IN ('global', 'sub_group', 'personal', 'custom'));

-- 3. Add column for custom split participant IDs
ALTER TABLE public.expenses 
  ADD COLUMN IF NOT EXISTS custom_split_participants uuid[] DEFAULT NULL;

-- Comment for documentation
COMMENT ON COLUMN public.expenses.custom_split_participants IS 
  'Array of participant IDs for custom split. Only used when scope = custom.';
