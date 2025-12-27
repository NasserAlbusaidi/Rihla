-- ============================================
-- 016: Add Expense Edit History
-- ============================================
-- This migration adds support for tracking expense edits.

-- 1. Create expense_history table to track edits
CREATE TABLE IF NOT EXISTS public.expense_history (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  expense_id uuid REFERENCES public.expenses(id) ON DELETE CASCADE NOT NULL,
  edited_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  old_amount decimal(12,3),
  new_amount decimal(12,3),
  old_description text,
  new_description text,
  old_scope text,
  new_scope text,
  edit_note text,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX idx_expense_history_expense_id ON public.expense_history(expense_id);

-- 2. Enable RLS on expense_history
ALTER TABLE public.expense_history ENABLE ROW LEVEL SECURITY;

-- 3. RLS policies for expense_history
CREATE POLICY "expense_history_select" ON public.expense_history
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.expenses e
      JOIN public.participants p ON p.trip_id = e.trip_id
      WHERE e.id = expense_history.expense_id
      AND p.user_id = auth.uid()
    )
  );

CREATE POLICY "expense_history_insert" ON public.expense_history
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.expenses e
      JOIN public.participants p ON p.trip_id = e.trip_id
      WHERE e.id = expense_history.expense_id
      AND p.user_id = auth.uid()
    )
  );

COMMENT ON TABLE public.expense_history IS 
  'Tracks all edits made to expenses for audit trail.';
