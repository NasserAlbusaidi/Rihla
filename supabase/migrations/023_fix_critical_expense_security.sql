-- ============================================
-- 023: Critical Security Fix - Expense RLS
-- ============================================
-- SECURITY FIX: Restrict UPDATE/DELETE to expense creator or trip leader
-- Previous policy allowed any trip member to modify any expense

-- Drop the insecure policies from migration 020
DROP POLICY IF EXISTS "expenses_update" ON public.expenses;
DROP POLICY IF EXISTS "expenses_delete" ON public.expenses;

-- Create secure UPDATE policy
-- Only the expense creator (payer) or trip leader can update an expense
CREATE POLICY "expenses_update" ON public.expenses FOR UPDATE TO authenticated
USING (
  -- User is the payer (owner of the expense)
  EXISTS (
    SELECT 1 FROM public.participants p
    WHERE p.id = payer_participant_id
    AND p.user_id = auth.uid()
  )
  OR 
  -- User is the trip leader (admin override)
  EXISTS (
    SELECT 1 FROM public.trips t
    WHERE t.id = trip_id 
    AND t.leader_id = auth.uid()
  )
);

-- Create secure DELETE policy
-- Only the expense creator (payer) or trip leader can delete an expense
CREATE POLICY "expenses_delete" ON public.expenses FOR DELETE TO authenticated
USING (
  -- User is the payer (owner of the expense)
  EXISTS (
    SELECT 1 FROM public.participants p
    WHERE p.id = payer_participant_id
    AND p.user_id = auth.uid()
  )
  OR 
  -- User is the trip leader (admin override)
  EXISTS (
    SELECT 1 FROM public.trips t
    WHERE t.id = trip_id 
    AND t.leader_id = auth.uid()
  )
);

-- Note: SELECT and INSERT policies remain unchanged (trip members can view and create expenses)
