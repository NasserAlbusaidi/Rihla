-- ============================================
-- SAFAR: Shadow Profile Migration v1.3.0
-- Adds: Shadow profiles, merge function, vanish rules
-- ============================================

-- ============================================
-- 1. PARTICIPANTS: Add shadow profile fields
-- ============================================

-- Add is_shadow flag for placeholder profiles
ALTER TABLE public.participants 
  ADD COLUMN IF NOT EXISTS is_shadow boolean DEFAULT false;

-- Add display_name for shadow profiles (real users use profiles table)
ALTER TABLE public.participants 
  ADD COLUMN IF NOT EXISTS display_name text;

-- Track who created the shadow
ALTER TABLE public.participants 
  ADD COLUMN IF NOT EXISTS created_by uuid REFERENCES auth.users(id);

-- Make user_id nullable for shadow profiles (drop NOT NULL constraint)
-- First drop the unique constraint, then alter column, then recreate constraint
ALTER TABLE public.participants DROP CONSTRAINT IF EXISTS participants_trip_id_user_id_key;
ALTER TABLE public.participants ALTER COLUMN user_id DROP NOT NULL;

-- Index for finding shadows
CREATE INDEX IF NOT EXISTS idx_participants_shadow 
  ON public.participants(trip_id, is_shadow);

-- ============================================
-- 2. MERGE SHADOW FUNCTION (Atomic)
-- ============================================
-- Transfers all data from shadow to real user, then marks shadow as merged

CREATE OR REPLACE FUNCTION merge_shadow_profile(
  p_shadow_id uuid,
  p_real_user_id uuid
)
RETURNS boolean AS $$
DECLARE
  v_trip_id uuid;
  v_shadow_display_name text;
BEGIN
  -- Get shadow info
  SELECT trip_id, display_name INTO v_trip_id, v_shadow_display_name
  FROM public.participants
  WHERE id = p_shadow_id AND is_shadow = true;
  
  IF v_trip_id IS NULL THEN
    RAISE EXCEPTION 'Shadow profile not found or not a shadow';
  END IF;
  
  -- Check real user exists in trip as new participant
  IF NOT EXISTS (
    SELECT 1 FROM public.participants 
    WHERE trip_id = v_trip_id AND user_id = p_real_user_id AND is_shadow = false
  ) THEN
    RAISE EXCEPTION 'Real user not found in this trip';
  END IF;
  
  -- Transfer expenses from shadow to real user
  UPDATE public.expenses 
  SET payer_id = p_real_user_id
  WHERE payer_id = p_shadow_id;
  
  -- Transfer sub_group memberships
  UPDATE public.sub_group_members
  SET user_id = p_real_user_id
  WHERE user_id = p_shadow_id;
  
  -- Delete the new participant record (real user joined fresh)
  DELETE FROM public.participants
  WHERE trip_id = v_trip_id AND user_id = p_real_user_id AND is_shadow = false;
  
  -- Update shadow to become the real user
  UPDATE public.participants
  SET 
    user_id = p_real_user_id,
    is_shadow = false,
    display_name = NULL
  WHERE id = p_shadow_id;
  
  RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 3. VANISH SHADOW FUNCTION (CASCADE delete)
-- ============================================
-- Deletes shadow and all associated data

CREATE OR REPLACE FUNCTION vanish_shadow_profile(
  p_shadow_id uuid
)
RETURNS boolean AS $$
DECLARE
  v_trip_id uuid;
BEGIN
  -- Get trip ID
  SELECT trip_id INTO v_trip_id
  FROM public.participants
  WHERE id = p_shadow_id AND is_shadow = true;
  
  IF v_trip_id IS NULL THEN
    RAISE EXCEPTION 'Shadow profile not found';
  END IF;
  
  -- Delete all expenses paid by shadow (using participant ID)
  DELETE FROM public.expenses 
  WHERE payer_id = p_shadow_id;
  
  -- Remove from sub_groups
  DELETE FROM public.sub_group_members
  WHERE user_id = p_shadow_id;
  
  -- Delete the shadow participant
  DELETE FROM public.participants
  WHERE id = p_shadow_id;
  
  RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 4. RLS POLICIES FOR SHADOW PROFILES
-- ============================================

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Leaders can create shadow profiles" ON public.participants;
DROP POLICY IF EXISTS "Leaders can manage shadow profiles" ON public.participants;
DROP POLICY IF EXISTS "Leaders can delete shadow profiles" ON public.participants;

-- Leaders can create shadows
CREATE POLICY "Leaders can create shadow profiles"
ON public.participants FOR INSERT
TO authenticated
WITH CHECK (
  is_shadow = true AND
  trip_id IN (SELECT id FROM public.trips WHERE leader_id = auth.uid())
);

-- Leaders can update shadows
CREATE POLICY "Leaders can manage shadow profiles"
ON public.participants FOR UPDATE
TO authenticated
USING (
  is_shadow = true AND
  trip_id IN (SELECT id FROM public.trips WHERE leader_id = auth.uid())
);

-- Leaders can delete shadows
CREATE POLICY "Leaders can delete shadow profiles"
ON public.participants FOR DELETE
TO authenticated
USING (
  is_shadow = true AND
  trip_id IN (SELECT id FROM public.trips WHERE leader_id = auth.uid())
);
