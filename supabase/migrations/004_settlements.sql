-- ============================================
-- 10. SETTLEMENTS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS public.settlements (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  trip_id uuid REFERENCES public.trips(id) ON DELETE CASCADE NOT NULL,
  payer_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  recipient_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  amount decimal(12,3) NOT NULL,
  currency text DEFAULT 'OMR',
  note text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Indexes (IF NOT EXISTS isn't standard in older Postgres for CREATE INDEX but usually fine to ignore or wrap, 
-- but Supabase usually handles idempotent index creation if name matches. 
-- To be safe, we'll use IF NOT EXISTS syntax which is supported in PG 9.5+)
CREATE INDEX IF NOT EXISTS idx_settlements_trip_id ON public.settlements(trip_id);
CREATE INDEX IF NOT EXISTS idx_settlements_payer_id ON public.settlements(payer_id);
CREATE INDEX IF NOT EXISTS idx_settlements_recipient_id ON public.settlements(recipient_id);

-- ============================================
-- ENABLE RLS
-- ============================================
ALTER TABLE public.settlements ENABLE ROW LEVEL SECURITY;

-- ============================================
-- POLICIES (Drop first to avoid exists error)
-- ============================================
DROP POLICY IF EXISTS "settlements_select" ON public.settlements;
CREATE POLICY "settlements_select" ON public.settlements FOR SELECT TO authenticated
  USING (public.is_trip_member(trip_id));

DROP POLICY IF EXISTS "settlements_insert" ON public.settlements;
CREATE POLICY "settlements_insert" ON public.settlements FOR INSERT TO authenticated
  WITH CHECK (public.is_trip_member(trip_id));

DROP POLICY IF EXISTS "settlements_update" ON public.settlements;
CREATE POLICY "settlements_update" ON public.settlements FOR UPDATE TO authenticated
  USING (payer_id = auth.uid() OR recipient_id = auth.uid());

DROP POLICY IF EXISTS "settlements_delete" ON public.settlements;
CREATE POLICY "settlements_delete" ON public.settlements FOR DELETE TO authenticated
  USING (payer_id = auth.uid() OR recipient_id = auth.uid() OR EXISTS (SELECT 1 FROM trips WHERE id = trip_id AND leader_id = auth.uid()));

-- ============================================
-- REALTIME
-- ============================================
-- Add to publication if not already added (safe to re-run usually, but 'alter publication add table' might error if already present)
-- We can wrap in a do block or just ignore if it fails, but cleaner to check.
-- For simplicity in this env, we'll try to add it. If it fails, it means it's already there.
do $$
begin
  alter publication supabase_realtime add table public.settlements;
exception when duplicate_object then
  null; -- table already in publication
end;
$$;
