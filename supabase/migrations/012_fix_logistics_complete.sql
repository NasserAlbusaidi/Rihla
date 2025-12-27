-- ============================================
-- FIX LOGISTICS - COMPLETE SOLUTION
-- ============================================

-- 1. Add missing columns to trips table
ALTER TABLE public.trips 
ADD COLUMN IF NOT EXISTS icon text DEFAULT 'airplane';

ALTER TABLE public.trips 
ADD COLUMN IF NOT EXISTS start_date date,
ADD COLUMN IF NOT EXISTS end_date date;

-- 2. Fix sub_group_members table completely
-- First, drop ALL constraints that might be blocking
ALTER TABLE public.sub_group_members 
DROP CONSTRAINT IF EXISTS sub_group_members_sub_group_id_user_id_key;

ALTER TABLE public.sub_group_members 
DROP CONSTRAINT IF EXISTS sub_group_members_sub_group_id_participant_id_key;

ALTER TABLE public.sub_group_members 
DROP CONSTRAINT IF EXISTS sub_group_members_participant_id_fkey;

-- Check if column exists, if not rename it
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'sub_group_members' AND column_name = 'user_id') THEN
        ALTER TABLE public.sub_group_members RENAME COLUMN user_id TO participant_id;
    END IF;
END $$;

-- Add the foreign key constraint properly
ALTER TABLE public.sub_group_members
ADD CONSTRAINT sub_group_members_participant_id_fkey 
FOREIGN KEY (participant_id) 
REFERENCES public.participants(id) 
ON DELETE CASCADE;

-- Add unique constraint
ALTER TABLE public.sub_group_members
ADD CONSTRAINT sub_group_members_sub_group_id_participant_id_key 
UNIQUE (sub_group_id, participant_id);

-- 3. Drop ALL RLS policies on sub_group_members and recreate them
DROP POLICY IF EXISTS "sub_group_members_select" ON public.sub_group_members;
DROP POLICY IF EXISTS "sub_group_members_insert" ON public.sub_group_members;
DROP POLICY IF EXISTS "sub_group_members_delete" ON public.sub_group_members;
DROP POLICY IF EXISTS "sub_group_members_update" ON public.sub_group_members;

-- Allow trip members to view sub_group_members
CREATE POLICY "sub_group_members_select" ON public.sub_group_members FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM sub_groups sg 
      WHERE sg.id = sub_group_id 
      AND public.is_trip_member(sg.trip_id)
    )
  );

-- Allow trip members to add members to sub_groups
CREATE POLICY "sub_group_members_insert" ON public.sub_group_members FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM sub_groups sg 
      WHERE sg.id = sub_group_id 
      AND public.is_trip_member(sg.trip_id)
    )
  );

-- Allow trip members to remove members from sub_groups
CREATE POLICY "sub_group_members_delete" ON public.sub_group_members FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM sub_groups sg 
      WHERE sg.id = sub_group_id 
      AND public.is_trip_member(sg.trip_id)
    )
  );

-- 4. Grant necessary permissions
GRANT ALL ON public.sub_group_members TO authenticated;
GRANT ALL ON public.sub_groups TO authenticated;
