-- 1. Add updated_at to sub_groups if it doesn't exist
DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='sub_groups' AND column_name='updated_at') THEN
        ALTER TABLE public.sub_groups ADD COLUMN updated_at timestamptz DEFAULT now();
    END IF;
END $$;

-- 2. Create function to touch sub_group when members change
CREATE OR REPLACE FUNCTION public.fn_touch_sub_group()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.sub_groups 
    SET updated_at = now()
    WHERE id = COALESCE(NEW.sub_group_id, OLD.sub_group_id);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- 3. Attach trigger to sub_group_members
DROP TRIGGER IF EXISTS tr_touch_sub_group_on_member_change ON public.sub_group_members;
CREATE TRIGGER tr_touch_sub_group_on_member_change
AFTER INSERT OR UPDATE OR DELETE ON public.sub_group_members
FOR EACH ROW EXECUTE FUNCTION public.fn_touch_sub_group();

-- 4. Redefine fn_log_activity to handle DISPLAY NAMES for shadow profiles in sub-groups
-- This ensures the activity feed shows the right name
CREATE OR REPLACE FUNCTION public.fn_log_activity()
RETURNS TRIGGER AS $$
DECLARE
    actor_uuid UUID;
    trip_uuid UUID;
    target_uuid UUID; 
    log_msg TEXT;
    evt_type TEXT;
    cat_type TEXT;
    meta_json JSONB;
    record_data RECORD;
    old_data RECORD;
    subject_name TEXT;
BEGIN
    actor_uuid := auth.uid();
    
    IF (TG_OP = 'INSERT') THEN
        evt_type := 'CREATE';
        record_data := NEW;
        trip_uuid := NEW.trip_id;
    ELSIF (TG_OP = 'UPDATE') THEN
        IF (OLD.is_deleted = false AND NEW.is_deleted = true) THEN
            evt_type := 'DELETE';
        ELSE
            evt_type := 'UPDATE';
        END IF;
        record_data := NEW;
        old_data := OLD;
        trip_uuid := NEW.trip_id;
    ELSIF (TG_OP = 'DELETE') THEN
        evt_type := 'DELETE';
        record_data := OLD;
        trip_uuid := OLD.trip_id;
    END IF;

    -- Special handling for trip_id if not on record (like sub_group_members)
    IF (trip_uuid IS NULL) THEN
        IF (TG_TABLE_NAME = 'sub_group_members') THEN
            SELECT trip_id INTO trip_uuid FROM public.sub_groups WHERE id = record_data.sub_group_id;
        END IF;
    END IF;

    IF (TG_TABLE_NAME = 'sub_group_members') THEN
        cat_type := 'LOGISTICS';
        target_uuid := record_data.participant_id;
        
        -- Get participant name for the log
        SELECT COALESCE(display_name, (SELECT display_name FROM public.profiles WHERE id = user_id), 'Unknown')
        INTO subject_name 
        FROM public.participants 
        WHERE id = target_uuid;

        IF (evt_type = 'CREATE') THEN
            log_msg := subject_name || ' joined ' || (SELECT name FROM public.sub_groups WHERE id = record_data.sub_group_id);
        ELSIF (evt_type = 'DELETE') THEN
            log_msg := subject_name || ' left ' || (SELECT name FROM public.sub_groups WHERE id = record_data.sub_group_id);
        END IF;

    ELSIF (TG_TABLE_NAME = 'expenses') THEN
        cat_type := 'MONEY';
        target_uuid := record_data.payer_participant_id;
        
        IF (evt_type = 'CREATE') THEN
            log_msg := 'Added expense: ' || COALESCE(record_data.description, 'Unknown');
        ELSIF (evt_type = 'DELETE') THEN
            log_msg := 'Deleted expense: ' || COALESCE(record_data.description, 'Unknown');
        ELSIF (evt_type = 'UPDATE') THEN
             log_msg := 'Updated expense: ' || COALESCE(record_data.description, 'Unknown');
             meta_json := jsonb_build_object('old_amount', old_data.amount, 'new_amount', record_data.amount);
        END IF;

    ELSIF (TG_TABLE_NAME = 'gear_items') THEN
        cat_type := 'GEAR';
        IF (record_data.assigned_to IS NOT NULL) THEN
             SELECT id INTO target_uuid FROM public.participants WHERE user_id = record_data.assigned_to AND trip_id = trip_uuid LIMIT 1;
        END IF;

        IF (evt_type = 'CREATE') THEN
            log_msg := 'Added gear: ' || record_data.item_name;
        ELSIF (evt_type = 'DELETE') THEN
            log_msg := 'Deleted gear: ' || record_data.item_name;
        ELSIF (evt_type = 'UPDATE') THEN
             IF (evt_type = 'UPDATE' AND old_data.is_packed != record_data.is_packed) THEN
                log_msg := CASE WHEN record_data.is_packed THEN 'Packed: ' ELSE 'Unpacked: ' END || record_data.item_name;
             ELSE
                log_msg := 'Updated gear: ' || record_data.item_name;
             END IF;
        END IF;

    ELSIF (TG_TABLE_NAME = 'documents') THEN
        cat_type := 'DOCS';
         IF (evt_type = 'CREATE') THEN
            log_msg := 'Added document: ' || record_data.file_name;
        ELSIF (evt_type = 'DELETE') THEN
            log_msg := 'Deleted document: ' || record_data.file_name;
        ELSIF (evt_type = 'UPDATE') THEN
             log_msg := 'Updated document: ' || record_data.file_name;
        END IF;
    
    ELSIF (TG_TABLE_NAME = 'settlements') THEN
        cat_type := 'MONEY';
        target_uuid := record_data.recipient_participant_id;

        IF (evt_type = 'CREATE') THEN
             log_msg := 'Recorded payment of ' || record_data.amount || ' ' || record_data.currency;
        ELSIF (evt_type = 'DELETE') THEN
             log_msg := 'Deleted payment of ' || record_data.amount || ' ' || record_data.currency;
        END IF;
    END IF;

    IF (log_msg IS NOT NULL) THEN
        INSERT INTO public.trip_activity_logs (trip_id, actor_id, target_participant_id, category, event_type, log_text, metadata)
        VALUES (trip_uuid, actor_uuid, target_uuid, cat_type, evt_type, log_msg, meta_json);
    END IF;

    IF (TG_OP = 'DELETE') THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Attach logging trigger to sub_group_members
DROP TRIGGER IF EXISTS tr_log_sub_group_members ON public.sub_group_members;
CREATE TRIGGER tr_log_sub_group_members AFTER INSERT OR DELETE ON public.sub_group_members
    FOR EACH ROW EXECUTE FUNCTION public.fn_log_activity();
