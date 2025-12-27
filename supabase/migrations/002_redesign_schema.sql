-- ============================================
-- SAFAR: Redesign Migration v1.2.0
-- Adds: trip dates, expense categories, settlements
-- ============================================

-- ============================================
-- 1. TRIPS: Add date fields
-- ============================================
ALTER TABLE public.trips ADD COLUMN IF NOT EXISTS start_date date;
ALTER TABLE public.trips ADD COLUMN IF NOT EXISTS end_date date;

-- ============================================
-- 2. EXPENSE_CATEGORIES: Custom categories per trip
-- ============================================
CREATE TABLE IF NOT EXISTS public.expense_categories (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  trip_id uuid REFERENCES public.trips(id) ON DELETE CASCADE NOT NULL,
  name text NOT NULL,
  icon text DEFAULT 'receipt', -- icon name like 'gas', 'food', etc.
  color text DEFAULT '#22C55E', -- hex color
  is_default boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  UNIQUE(trip_id, name)
);

CREATE INDEX idx_expense_categories_trip_id ON public.expense_categories(trip_id);

-- ============================================
-- 3. EXPENSES: Add category reference + note
-- ============================================
ALTER TABLE public.expenses 
  ADD COLUMN IF NOT EXISTS category_id uuid REFERENCES public.expense_categories(id) ON DELETE SET NULL;
ALTER TABLE public.expenses 
  ADD COLUMN IF NOT EXISTS note text;

-- ============================================
-- 4. SUB_GROUPS: Add vehicle details
-- ============================================
ALTER TABLE public.sub_groups 
  ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE public.sub_groups 
  ADD COLUMN IF NOT EXISTS image_url text;

-- ============================================
-- 5. SETTLEMENTS: Track debt payments
-- ============================================
CREATE TABLE IF NOT EXISTS public.settlements (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  trip_id uuid REFERENCES public.trips(id) ON DELETE CASCADE NOT NULL,
  payer_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  recipient_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  amount decimal(12,3) NOT NULL,
  note text,
  settled_at timestamptz DEFAULT now()
);

CREATE INDEX idx_settlements_trip_id ON public.settlements(trip_id);

-- ============================================
-- 6. RLS POLICIES
-- ============================================

-- Expense Categories: Trip members can view, leaders can insert/update/delete
ALTER TABLE public.expense_categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Trip members can view categories"
ON public.expense_categories FOR SELECT
TO authenticated
USING (trip_id IN (SELECT trip_id FROM public.participants WHERE user_id = auth.uid()));

CREATE POLICY "Trip leaders can manage categories"
ON public.expense_categories FOR ALL
TO authenticated
USING (
  trip_id IN (
    SELECT id FROM public.trips WHERE leader_id = auth.uid()
  )
);

-- Settlements: Trip members can view, participants can insert
ALTER TABLE public.settlements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Trip members can view settlements"
ON public.settlements FOR SELECT
TO authenticated
USING (trip_id IN (SELECT trip_id FROM public.participants WHERE user_id = auth.uid()));

CREATE POLICY "Trip members can insert settlements"
ON public.settlements FOR INSERT
TO authenticated
WITH CHECK (trip_id IN (SELECT trip_id FROM public.participants WHERE user_id = auth.uid()));

-- ============================================
-- 7. DEFAULT CATEGORIES FUNCTION
-- ============================================
CREATE OR REPLACE FUNCTION create_default_categories()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.expense_categories (trip_id, name, icon, is_default) VALUES
    (NEW.id, 'Gas', 'gas', true),
    (NEW.id, 'Food', 'food', true),
    (NEW.id, 'Gear', 'gear', true),
    (NEW.id, 'Lodging', 'lodging', true),
    (NEW.id, 'Transport', 'transport', true),
    (NEW.id, 'Other', 'other', true);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to auto-create default categories when trip is created
DROP TRIGGER IF EXISTS on_trip_created_categories ON public.trips;
CREATE TRIGGER on_trip_created_categories
  AFTER INSERT ON public.trips
  FOR EACH ROW
  EXECUTE FUNCTION create_default_categories();
