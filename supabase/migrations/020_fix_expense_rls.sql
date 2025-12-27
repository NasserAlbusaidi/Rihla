-- ============================================
-- 020: Fix Expense RLS Policies
-- ============================================
-- Updates expense RLS to work with payer_participant_id and allow trip members to update

-- Drop old policies
DROP POLICY IF EXISTS "expenses_update" ON public.expenses;
DROP POLICY IF EXISTS "expenses_delete" ON public.expenses;

-- Create updated UPDATE policy (trip members can update expenses)
CREATE POLICY "expenses_update" ON public.expenses FOR UPDATE TO authenticated
  USING (public.is_trip_member(trip_id));

-- Create updated DELETE policy (trip members can delete expenses)  
CREATE POLICY "expenses_delete" ON public.expenses FOR DELETE TO authenticated
  USING (public.is_trip_member(trip_id));
