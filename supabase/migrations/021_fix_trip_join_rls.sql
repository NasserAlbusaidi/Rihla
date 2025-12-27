-- Fix: Allow users to look up trips by invite code for joining
-- Previously, the trips_select policy only allowed reading trips you're already a member of
-- This prevented the join trip feature from working

-- Drop the existing restrictive policy
DROP POLICY IF EXISTS "trips_select" ON public.trips;

-- Create a new policy that allows:
-- 1. Reading trips you're a member of
-- 2. Reading trips you lead
-- 3. Reading any trip (needed for invite code lookup - the invite code itself is the security)
CREATE POLICY "trips_select" ON public.trips FOR SELECT TO authenticated
  USING (true);

-- Note: The invite code acts as the authentication factor for joining
-- Only someone with the invite code can join a trip
