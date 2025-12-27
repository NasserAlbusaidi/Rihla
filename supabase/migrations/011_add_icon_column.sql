-- ============================================
-- FIX LOGISTICS ISSUES
-- ============================================

-- 1. Add missing icon column to trips table
ALTER TABLE public.trips 
ADD COLUMN IF NOT EXISTS icon text DEFAULT 'airplane';

-- 2. Add start_date and end_date if missing
ALTER TABLE public.trips 
ADD COLUMN IF NOT EXISTS start_date date,
ADD COLUMN IF NOT EXISTS end_date date;

-- 3. Fix broken UNIQUE constraint on sub_group_members
-- The old constraint referenced 'user_id' but we renamed it to 'participant_id'
ALTER TABLE public.sub_group_members 
DROP CONSTRAINT IF EXISTS sub_group_members_sub_group_id_user_id_key;

ALTER TABLE public.sub_group_members
ADD CONSTRAINT sub_group_members_sub_group_id_participant_id_key 
UNIQUE (sub_group_id, participant_id);

-- 4. Fix RLS policy for sub_group_members INSERT
-- The current policy may be blocking inserts
DROP POLICY IF EXISTS "sub_group_members_insert" ON public.sub_group_members;
CREATE POLICY "sub_group_members_insert" ON public.sub_group_members FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM sub_groups sg 
      WHERE sg.id = sub_group_id 
      AND public.is_trip_member(sg.trip_id)
    )
  );

-- 5. Fix RLS policy for sub_group_members DELETE
DROP POLICY IF EXISTS "sub_group_members_delete" ON public.sub_group_members;
CREATE POLICY "sub_group_members_delete" ON public.sub_group_members FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM sub_groups sg 
      WHERE sg.id = sub_group_id 
      AND public.is_trip_member(sg.trip_id)
    )
  );
