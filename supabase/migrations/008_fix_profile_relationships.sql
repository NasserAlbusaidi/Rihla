-- 1. DISABLE TRIGGERS temporarily to avoid "column not found" errors during rename
DROP TRIGGER IF EXISTS tr_log_expenses ON public.expenses;
DROP TRIGGER IF EXISTS tr_log_settlements ON public.settlements;

-- 2. PARTICIPANTS: Link user_id directly to public.profiles
ALTER TABLE public.participants 
  DROP CONSTRAINT IF EXISTS participants_user_id_fkey;

ALTER TABLE public.participants
  ADD CONSTRAINT participants_user_id_profiles_fkey 
  FOREIGN KEY (user_id) 
  REFERENCES public.profiles(id) 
  ON DELETE CASCADE;

-- 3. SUB_GROUP_MEMBERS: Re-target to participants.id
ALTER TABLE public.sub_group_members 
  DROP CONSTRAINT IF EXISTS sub_group_members_user_id_fkey;

ALTER TABLE public.sub_group_members 
  RENAME COLUMN user_id TO participant_id;

-- Convert existing User IDs to Participant IDs
UPDATE public.sub_group_members sgm
SET participant_id = p.id
FROM public.participants p, public.sub_groups sg
WHERE sg.id = sgm.sub_group_id
AND p.user_id = sgm.participant_id
AND p.trip_id = sg.trip_id;

ALTER TABLE public.sub_group_members
  ADD CONSTRAINT sub_group_members_participant_id_fkey 
  FOREIGN KEY (participant_id) 
  REFERENCES public.participants(id) 
  ON DELETE CASCADE;

-- 4. EXPENSES: Re-target payer_id to participants.id
ALTER TABLE public.expenses 
  DROP CONSTRAINT IF EXISTS expenses_payer_id_fkey;

ALTER TABLE public.expenses 
  RENAME COLUMN payer_id TO payer_participant_id;

-- Convert existing User IDs to Participant IDs
UPDATE public.expenses e
SET payer_participant_id = p.id
FROM public.participants p
WHERE p.user_id = e.payer_participant_id
AND p.trip_id = e.trip_id;

ALTER TABLE public.expenses
  ADD CONSTRAINT expenses_payer_participant_id_fkey 
  FOREIGN KEY (payer_participant_id) 
  REFERENCES public.participants(id) 
  ON DELETE SET NULL;

-- 5. SETTLEMENTS: Re-target to participants.id
ALTER TABLE public.settlements 
  DROP CONSTRAINT IF EXISTS settlements_payer_id_fkey,
  DROP CONSTRAINT IF EXISTS settlements_recipient_id_fkey;

ALTER TABLE public.settlements 
  RENAME COLUMN payer_id TO payer_participant_id;
ALTER TABLE public.settlements 
  RENAME COLUMN recipient_id TO recipient_participant_id;

-- Convert existing User IDs to Participant IDs (Payer)
UPDATE public.settlements s
SET payer_participant_id = p.id
FROM public.participants p
WHERE p.user_id = s.payer_participant_id
AND p.trip_id = s.trip_id;

-- Convert existing User IDs to Participant IDs (Recipient)
UPDATE public.settlements s
SET recipient_participant_id = p.id
FROM public.participants p
WHERE p.user_id = s.recipient_participant_id
AND p.trip_id = s.trip_id;

ALTER TABLE public.settlements
  ADD CONSTRAINT settlements_payer_participant_id_fkey 
  FOREIGN KEY (payer_participant_id) 
  REFERENCES public.participants(id) 
  ON DELETE SET NULL,
  ADD CONSTRAINT settlements_recipient_participant_id_fkey 
  FOREIGN KEY (recipient_participant_id) 
  REFERENCES public.participants(id) 
  ON DELETE SET NULL;

-- 6. UPDATE AUDIT LOG TRIGGER FUNCTION
-- We must redefine it because it referred to 'payer_id' and 'recipient_id'
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

    IF (TG_TABLE_NAME = 'expenses') THEN
        cat_type := 'MONEY';
        -- Now points directly to participant_id
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
        -- Now points directly to participant_id
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

-- 7. RE-ATTACH TRIGGERS
CREATE TRIGGER tr_log_expenses AFTER INSERT OR UPDATE OR DELETE ON public.expenses
    FOR EACH ROW EXECUTE FUNCTION public.fn_log_activity();

CREATE TRIGGER tr_log_settlements AFTER INSERT OR UPDATE OR DELETE ON public.settlements
    FOR EACH ROW EXECUTE FUNCTION public.fn_log_activity();
