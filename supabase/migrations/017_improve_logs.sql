-- ============================================
-- 017: Improve Activity Logs for Expenses
-- ============================================
-- This migration improves the expense log messages to show more detail
-- (amount, category, who paid) instead of just "Unknown"

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
    expense_desc TEXT;
    category_name TEXT;
BEGIN
    actor_uuid := auth.uid();
    
    -- Determine Event Type & Record
    IF (TG_OP = 'INSERT') THEN
        evt_type := 'CREATE';
        record_data := NEW;
    ELSIF (TG_OP = 'UPDATE') THEN
        evt_type := 'UPDATE';
        record_data := NEW;
        old_data := OLD;
    ELSIF (TG_OP = 'DELETE') THEN
        evt_type := 'DELETE';
        record_data := OLD;
    END IF;

    -- Handle sub_group_members FIRST (it doesn't have trip_id column)
    IF (TG_TABLE_NAME = 'sub_group_members') THEN
        cat_type := 'LOGISTICS';
        target_uuid := record_data.participant_id;
        
        -- Get trip_id from sub_groups table
        SELECT trip_id INTO trip_uuid FROM public.sub_groups WHERE id = record_data.sub_group_id;
        
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

    -- All other tables have trip_id column
    ELSE
        -- Get trip_id from the record (these tables have trip_id)
        IF (TG_OP = 'DELETE') THEN
            trip_uuid := OLD.trip_id;
        ELSE
            trip_uuid := NEW.trip_id;
        END IF;

        -- Check for soft delete
        IF (TG_OP = 'UPDATE' AND OLD.is_deleted = false AND NEW.is_deleted = true) THEN
            evt_type := 'DELETE';
        END IF;

        IF (TG_TABLE_NAME = 'expenses') THEN
            cat_type := 'MONEY';
            target_uuid := record_data.payer_participant_id;
            
            -- Get category name if available
            IF record_data.category_id IS NOT NULL THEN
                SELECT name INTO category_name FROM public.expense_categories WHERE id = record_data.category_id;
            END IF;
            
            -- Get payer name
            SELECT COALESCE(display_name, (SELECT display_name FROM public.profiles WHERE id = user_id), 'Someone')
            INTO subject_name 
            FROM public.participants 
            WHERE id = target_uuid;
            
            -- Build a more descriptive expense description
            expense_desc := COALESCE(
                record_data.description,
                category_name,
                'expense'
            );
            
            IF (evt_type = 'CREATE') THEN
                log_msg := subject_name || ' paid ' || record_data.amount || ' OMR for ' || expense_desc;
                meta_json := jsonb_build_object(
                    'amount', record_data.amount,
                    'category', category_name,
                    'scope', record_data.scope
                );
            ELSIF (evt_type = 'DELETE') THEN
                log_msg := 'Deleted: ' || expense_desc || ' (' || record_data.amount || ' OMR)';
                meta_json := jsonb_build_object('is_deleted', true);
            ELSIF (evt_type = 'UPDATE') THEN
                log_msg := 'Updated ' || expense_desc;
                meta_json := jsonb_build_object(
                    'old_amount', old_data.amount, 
                    'new_amount', record_data.amount
                );
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
                IF (old_data.is_packed != record_data.is_packed) THEN
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
            
            -- Get payer and recipient names
            DECLARE
                payer_name TEXT;
                recipient_name TEXT;
            BEGIN
                SELECT COALESCE(display_name, 'Someone') INTO payer_name 
                FROM public.participants WHERE id = record_data.payer_participant_id;
                
                SELECT COALESCE(display_name, 'someone') INTO recipient_name 
                FROM public.participants WHERE id = record_data.recipient_participant_id;
                
                IF (evt_type = 'CREATE') THEN
                    log_msg := payer_name || ' paid ' || recipient_name || ' ' || record_data.amount || ' ' || record_data.currency;
                ELSIF (evt_type = 'DELETE') THEN
                    log_msg := 'Deleted payment: ' || record_data.amount || ' ' || record_data.currency;
                END IF;
            END;
        END IF;
    END IF;

    -- Insert Log (Only if we generated a message)
    IF (log_msg IS NOT NULL AND trip_uuid IS NOT NULL) THEN
        INSERT INTO public.trip_activity_logs (trip_id, actor_id, target_participant_id, category, event_type, log_text, metadata)
        VALUES (trip_uuid, actor_uuid, target_uuid, cat_type, evt_type, log_msg, meta_json);
    END IF;

    IF (TG_OP = 'DELETE') THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
