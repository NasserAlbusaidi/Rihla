-- ============================================
-- HOTFIX: Fix RLS policies for name-based member system
-- Three critical bugs:
--   1. Leaders can't insert participants with user_id = null
--   2. No UPDATE policy on participants (claim flow blocked)
--   3. Settlement update policy compares wrong UUID types
-- ============================================

-- ============================================
-- FIX 1: Allow trip leaders to add participants
-- ============================================
-- The original participants_insert policy (WITH CHECK user_id = auth.uid())
-- blocks inserting members with user_id = null (name-based members).
-- This new policy allows trip leaders to insert any participant into their trip.
DROP POLICY IF EXISTS "leaders_insert_participants" ON public.participants;
CREATE POLICY "leaders_insert_participants"
ON public.participants FOR INSERT
TO authenticated
WITH CHECK (
  trip_id IN (SELECT id FROM public.trips WHERE leader_id = auth.uid())
);

-- ============================================
-- FIX 2: Allow claiming unclaimed participants
-- ============================================
-- No UPDATE policy existed for regular participants.
-- The shadow profile update policy requires is_shadow = true.
-- This allows:
--   a) Claiming an unclaimed participant (user_id IS NULL → set to self)
--   b) Updating your own participant record
DROP POLICY IF EXISTS "participants_update" ON public.participants;
CREATE POLICY "participants_update"
ON public.participants FOR UPDATE
TO authenticated
USING (
  user_id IS NULL
  OR user_id = auth.uid()
  OR trip_id IN (SELECT id FROM public.trips WHERE leader_id = auth.uid())
)
WITH CHECK (
  user_id = auth.uid()
  OR trip_id IN (SELECT id FROM public.trips WHERE leader_id = auth.uid())
);

-- ============================================
-- FIX 3: Fix settlements update policy
-- ============================================
-- The old policy compared payer_participant_id directly with auth.uid(),
-- but payer_participant_id is a participant UUID, not a user UUID.
-- This could never match, so settlements could never be updated.
DROP POLICY IF EXISTS "settlements_update" ON public.settlements;
CREATE POLICY "settlements_update" ON public.settlements FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.participants p
    WHERE (p.id = payer_participant_id OR p.id = recipient_participant_id)
    AND p.user_id = auth.uid()
  )
  OR EXISTS (
    SELECT 1 FROM public.trips t
    WHERE t.id = trip_id AND t.leader_id = auth.uid()
  )
);
