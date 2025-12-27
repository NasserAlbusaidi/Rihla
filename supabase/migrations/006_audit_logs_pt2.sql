-- ============================================
-- 11. AUDIT LOGS - PART 2: IDENTITY MERGE SYNC
-- ============================================

-- Function to update historical logs when a Shadow Profile merges into a Real User
CREATE OR REPLACE FUNCTION public.fn_update_log_names()
RETURNS TRIGGER AS $$
DECLARE
    v_real_name text;
    v_old_shadow_name text;
BEGIN
    -- Only run if a shadow is becoming a real user (is_shadow true -> false)
    IF (OLD.is_shadow = true AND NEW.is_shadow = false AND NEW.user_id IS NOT NULL) THEN
        
        -- Get the real user's display name from profiles
        SELECT display_name INTO v_real_name
        FROM public.profiles
        WHERE id = NEW.user_id;

        v_old_shadow_name := OLD.display_name;

        -- If we have both names, update the logs
        IF (v_real_name IS NOT NULL AND v_old_shadow_name IS NOT NULL) THEN
            
            -- Update logs for this participant
            -- We do a text replacement. 
            -- NOTE: This is a simple replacement. In complex strings it might replace wrong parts, 
            -- but for "Added expense for Batman", it works well.
            UPDATE public.trip_activity_logs
            SET log_text = REPLACE(log_text, v_old_shadow_name, v_real_name)
            WHERE target_participant_id = NEW.id;
            
        END IF;

    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger on participants
DROP TRIGGER IF EXISTS tr_sync_log_names ON public.participants;
CREATE TRIGGER tr_sync_log_names
    AFTER UPDATE ON public.participants
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_update_log_names();
