-- ============================================
-- 015: Add Receipt URL to Expenses
-- ============================================
-- This migration adds support for attaching receipt images to expenses.

ALTER TABLE public.expenses 
  ADD COLUMN IF NOT EXISTS receipt_url text DEFAULT NULL;

COMMENT ON COLUMN public.expenses.receipt_url IS 
  'URL of the receipt image stored in Supabase Storage.';
