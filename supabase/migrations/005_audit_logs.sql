-- ============================================
-- 11. AUDIT LOGS & SOFT DELETES
-- ============================================

-- 11.1 Add Soft Delete Columns to Primary Tables
ALTER TABLE public.expenses 
ADD COLUMN IF NOT EXISTS is_deleted boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS deleted_at timestamptz;

ALTER TABLE public.gear_items 
ADD COLUMN IF NOT EXISTS is_deleted boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS deleted_at timestamptz;

ALTER TABLE public.documents 
ADD COLUMN IF NOT EXISTS is_deleted boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS deleted_at timestamptz;

ALTER TABLE public.settlements 
ADD COLUMN IF NOT EXISTS is_deleted boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS deleted_at timestamptz;

-- 11.2 Create Audit Logs Table
CREATE TABLE IF NOT EXISTS public.trip_activity_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    trip_id UUID REFERENCES public.trips(id) ON DELETE CASCADE NOT NULL,
    actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    target_participant_id UUID REFERENCES public.participants(id) ON DELETE SET NULL,
    category TEXT NOT NULL, -- 'MONEY', 'GEAR', 'DOCS', 'LOGISTICS', 'MEMBER'
    event_type TEXT NOT NULL, -- 'CREATE', 'UPDATE', 'DELETE', 'SETTLE', 'JOIN'
    log_text TEXT NOT NULL,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_logs_trip_id ON public.trip_activity_logs(trip_id);
CREATE INDEX IF NOT EXISTS idx_logs_participant_id ON public.trip_activity_logs(target_participant_id); 

-- RLS
ALTER TABLE public.trip_activity_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "logs_select" ON public.trip_activity_logs;
CREATE POLICY "logs_select" ON public.trip_activity_logs FOR SELECT TO authenticated
  USING (public.is_trip_member(trip_id));

-- Realtime
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'trip_activity_logs') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.trip_activity_logs;
  END IF;
END;
$$;


-- 11.3 Universal Logging Trigger Function
-- UPDATED in 008 to handle participant_id directly
CREATE OR REPLACE FUNCTION public.fn_log_activity()
RETURNS TRIGGER AS $$
DECLARE
    actor_uuid UUID;
    trip_uuid UUID;
    target_uuid UUID; -- Participant ID if applicable
    log_msg TEXT;
    evt_type TEXT;
    cat_type TEXT;
    meta_json JSONB;
    
    -- Helper vars
    record_data RECORD;
    old_data RECORD;
BEGIN
    -- Get current user (Actor)
    actor_uuid := auth.uid();
    
    -- Determine Event Type & Record
    IF (TG_OP = 'INSERT') THEN
        evt_type := 'CREATE';
        record_data := NEW;
        trip_uuid := NEW.trip_id;
    ELSIF (TG_OP = 'UPDATE') THEN
        -- Check if it's a soft delete
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

    -- Determine Category & Message based on Table
    IF (TG_TABLE_NAME = 'expenses') THEN
        cat_type := 'MONEY';
        -- Points directly to payer_participant_id (Updated in 008)
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
        -- Try to map assigned_to (user_id) to participant_id
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
        -- Points directly to recipient_participant_id (Updated in 008)
        target_uuid := record_data.recipient_participant_id;

        IF (evt_type = 'CREATE') THEN
             log_msg := 'Recorded payment of ' || record_data.amount || ' ' || record_data.currency;
        ELSIF (evt_type = 'DELETE') THEN
             log_msg := 'Deleted payment of ' || record_data.amount || ' ' || record_data.currency;
        END IF;
    END IF;

    -- Insert Log (Only if we generated a message)
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

-- 11.4 Attach Triggers
DROP TRIGGER IF EXISTS tr_log_expenses ON public.expenses;
CREATE TRIGGER tr_log_expenses AFTER INSERT OR UPDATE OR DELETE ON public.expenses
    FOR EACH ROW EXECUTE FUNCTION public.fn_log_activity();

DROP TRIGGER IF EXISTS tr_log_gear ON public.gear_items;
CREATE TRIGGER tr_log_gear AFTER INSERT OR UPDATE OR DELETE ON public.gear_items
    FOR EACH ROW EXECUTE FUNCTION public.fn_log_activity();

DROP TRIGGER IF EXISTS tr_log_documents ON public.documents;
CREATE TRIGGER tr_log_documents AFTER INSERT OR UPDATE OR DELETE ON public.documents
    FOR EACH ROW EXECUTE FUNCTION public.fn_log_activity();

DROP TRIGGER IF EXISTS tr_log_settlements ON public.settlements;
CREATE TRIGGER tr_log_settlements AFTER INSERT OR UPDATE OR DELETE ON public.settlements
    FOR EACH ROW EXECUTE FUNCTION public.fn_log_activity();
