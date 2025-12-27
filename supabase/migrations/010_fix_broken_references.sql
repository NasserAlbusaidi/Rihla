-- ============================================
-- 1. FIX BROKEN RLS POLICIES (Due to column renames in 008)
-- ============================================

-- sub_group_members: user_id -> participant_id
DROP POLICY IF EXISTS "sub_group_members_delete" ON public.sub_group_members;
CREATE POLICY "sub_group_members_delete" ON public.sub_group_members FOR DELETE TO authenticated
  USING (
    participant_id IN (
        SELECT id FROM public.participants WHERE user_id = auth.uid()
    )
  );

-- expenses: payer_id -> payer_participant_id
DROP POLICY IF EXISTS "expenses_update" ON public.expenses;
CREATE POLICY "expenses_update" ON public.expenses FOR UPDATE TO authenticated
  USING (
    payer_participant_id IN (
        SELECT id FROM public.participants WHERE user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "expenses_delete" ON public.expenses;
CREATE POLICY "expenses_delete" ON public.expenses FOR DELETE TO authenticated
  USING (
    payer_participant_id IN (
        SELECT id FROM public.participants WHERE user_id = auth.uid()
    ) 
    OR 
    EXISTS (SELECT 1 FROM trips WHERE id = trip_id AND leader_id = auth.uid())
  );

-- settlements: payer_id -> payer_participant_id, recipient_id -> recipient_participant_id
DROP POLICY IF EXISTS "settlements_delete" ON public.settlements;
CREATE POLICY "settlements_delete" ON public.settlements FOR DELETE TO authenticated
  USING (
    payer_participant_id IN (
        SELECT id FROM public.participants WHERE user_id = auth.uid()
    )
    OR 
    EXISTS (SELECT 1 FROM trips WHERE id = trip_id AND leader_id = auth.uid())
  );

-- ============================================
-- 2. FIX BROKEN FUNCTIONS (Due to column renames in 008)
-- ============================================

-- Update merge_shadow_profile to use new column names and logic
CREATE OR REPLACE FUNCTION merge_shadow_profile(
  p_shadow_id uuid,
  p_real_user_id uuid
)
RETURNS boolean AS $$
DECLARE
  v_trip_id uuid;
  v_real_participant_id uuid;
BEGIN
  -- 1. Get shadow info
  SELECT trip_id INTO v_trip_id
  FROM public.participants
  WHERE id = p_shadow_id AND is_shadow = true;
  
  IF v_trip_id IS NULL THEN
    RAISE EXCEPTION 'Shadow profile not found or not a shadow';
  END IF;
  
  -- 2. Find the real user's participant record in this trip
  SELECT id INTO v_real_participant_id
  FROM public.participants 
  WHERE trip_id = v_trip_id AND user_id = p_real_user_id AND is_shadow = false;

  IF v_real_participant_id IS NULL THEN
    RAISE EXCEPTION 'Real user not found in this trip';
  END IF;
  
  -- 3. Transfer any activity from the real user's temporary participant record TO the shadow record
  UPDATE public.expenses 
  SET payer_participant_id = p_shadow_id
  WHERE payer_participant_id = v_real_participant_id;
  
  UPDATE public.sub_group_members
  SET participant_id = p_shadow_id
  WHERE participant_id = v_real_participant_id;

  UPDATE public.settlements
  SET payer_participant_id = p_shadow_id
  WHERE payer_participant_id = v_real_participant_id;

  UPDATE public.settlements
  SET recipient_participant_id = p_shadow_id
  WHERE recipient_participant_id = v_real_participant_id;
  
  -- 4. Delete the now-empty real participant record 
  DELETE FROM public.participants
  WHERE id = v_real_participant_id;
  
  -- 5. Update shadow to become the real user's record
  UPDATE public.participants
  SET 
    user_id = p_real_user_id,
    is_shadow = false,
    display_name = NULL
  WHERE id = p_shadow_id;
  
  RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update vanish_shadow_profile to use new column names
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
  
  -- 1. Delete all expenses paid by shadow (using participant ID)
  DELETE FROM public.expenses 
  WHERE payer_participant_id = p_shadow_id;
  
  -- 2. Remove from sub_groups
  DELETE FROM public.sub_group_members
  WHERE participant_id = p_shadow_id;
  
  -- 3. Delete the shadow participant
  DELETE FROM public.participants
  WHERE id = p_shadow_id;
  
  RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
