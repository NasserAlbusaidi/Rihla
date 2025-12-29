-- ============================================
-- 024: Activity Log Trigger with Names
-- ============================================

CREATE OR REPLACE FUNCTION public.fn_log_activity()
RETURNS TRIGGER AS $$
DECLARE
    trip_uuid UUID;
    log_msg TEXT;
    cat_type TEXT;
    evt_type TEXT;
    actor_name TEXT := 'User';
BEGIN
    -- Get actor name from profiles (safe even if no profile exists)
    SELECT COALESCE(display_name, split_part(email, '@', 1), 'User') 
    INTO actor_name
    FROM public.profiles 
    WHERE id = auth.uid();
    
    IF actor_name IS NULL THEN
        actor_name := 'User';
    END IF;

    -- Determine event type
    IF (TG_OP = 'INSERT') THEN
        evt_type := 'CREATE';
    ELSIF (TG_OP = 'UPDATE') THEN
        evt_type := 'UPDATE';
    ELSE
        evt_type := 'DELETE';
    END IF;

    -- Get trip_id from NEW or OLD
    IF (TG_OP = 'DELETE') THEN
        trip_uuid := OLD.trip_id;
    ELSE
        trip_uuid := NEW.trip_id;
    END IF;

    -- Handle different tables
    IF (TG_TABLE_NAME = 'expenses') THEN
        cat_type := 'MONEY';
        IF evt_type = 'CREATE' THEN
            log_msg := actor_name || ' paid ' || NEW.amount || ' OMR for ' || COALESCE(NEW.description, 'expense');
        ELSIF NEW.is_deleted = true AND OLD.is_deleted = false THEN
            evt_type := 'DELETE';
            log_msg := actor_name || ' deleted expense: ' || COALESCE(NEW.description, 'item');
        ELSE
            log_msg := actor_name || ' updated expense: ' || COALESCE(NEW.description, 'item');
        END IF;
        
    ELSIF (TG_TABLE_NAME = 'gear_items') THEN
        cat_type := 'GEAR';
        IF evt_type = 'CREATE' THEN
            log_msg := actor_name || ' added gear: ' || COALESCE(NEW.item_name, 'item');
        ELSIF NEW.is_deleted = true AND OLD.is_deleted = false THEN
            evt_type := 'DELETE';
            log_msg := actor_name || ' deleted gear: ' || COALESCE(NEW.item_name, 'item');
        ELSIF NEW.is_packed IS DISTINCT FROM OLD.is_packed THEN
            IF NEW.is_packed = true THEN
                log_msg := actor_name || ' packed: ' || COALESCE(NEW.item_name, 'item');
            ELSE
                log_msg := actor_name || ' unpacked: ' || COALESCE(NEW.item_name, 'item');
            END IF;
        ELSIF NEW.assigned_to IS DISTINCT FROM OLD.assigned_to THEN
            IF NEW.assigned_to IS NOT NULL THEN
                log_msg := actor_name || ' claimed: ' || COALESCE(NEW.item_name, 'item');
            ELSE
                log_msg := actor_name || ' unclaimed: ' || COALESCE(NEW.item_name, 'item');
            END IF;
        ELSE
            log_msg := actor_name || ' updated gear: ' || COALESCE(NEW.item_name, 'item');
        END IF;
        
    ELSIF (TG_TABLE_NAME = 'documents') THEN
        cat_type := 'DOCS';
        log_msg := actor_name || ' added document: ' || COALESCE(NEW.file_name, 'file');
        
    ELSIF (TG_TABLE_NAME = 'settlements') THEN
        cat_type := 'MONEY';
        log_msg := actor_name || ' recorded payment: ' || COALESCE(NEW.amount::text, '0') || ' ' || COALESCE(NEW.currency, 'OMR');
        
    ELSIF (TG_TABLE_NAME = 'sub_group_members') THEN
        IF (TG_OP = 'DELETE') THEN RETURN OLD; END IF;
        RETURN NEW;
    ELSE
        IF (TG_OP = 'DELETE') THEN RETURN OLD; END IF;
        RETURN NEW;
    END IF;

    -- Insert the log
    IF trip_uuid IS NOT NULL AND log_msg IS NOT NULL THEN
        INSERT INTO public.trip_activity_logs (trip_id, actor_id, category, event_type, log_text)
        VALUES (trip_uuid, auth.uid(), cat_type, evt_type, log_msg);
    END IF;

    IF (TG_OP = 'DELETE') THEN RETURN OLD; END IF;
    RETURN NEW;
    
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_log_activity error: % - %', SQLSTATE, SQLERRM;
    IF (TG_OP = 'DELETE') THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Re-attach triggers
DROP TRIGGER IF EXISTS tr_log_expenses ON public.expenses;
CREATE TRIGGER tr_log_expenses AFTER INSERT OR UPDATE ON public.expenses
    FOR EACH ROW EXECUTE FUNCTION public.fn_log_activity();

DROP TRIGGER IF EXISTS tr_log_gear ON public.gear_items;
CREATE TRIGGER tr_log_gear AFTER INSERT OR UPDATE ON public.gear_items
    FOR EACH ROW EXECUTE FUNCTION public.fn_log_activity();

DROP TRIGGER IF EXISTS tr_log_documents ON public.documents;
CREATE TRIGGER tr_log_documents AFTER INSERT OR UPDATE ON public.documents
    FOR EACH ROW EXECUTE FUNCTION public.fn_log_activity();

DROP TRIGGER IF EXISTS tr_log_settlements ON public.settlements;
CREATE TRIGGER tr_log_settlements AFTER INSERT OR UPDATE ON public.settlements
    FOR EACH ROW EXECUTE FUNCTION public.fn_log_activity();
