-- ============================================
-- SAFAR: Project Rihla - Initial Schema
-- Version: 1.1.0 (Fixed RLS policies)
-- Run this in your Supabase SQL Editor
-- ============================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- 1. TRIPS TABLE
-- ============================================
CREATE TABLE public.trips (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  invite_code text UNIQUE NOT NULL,
  leader_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  modules jsonb DEFAULT '{"docs": true, "gear": true, "itinerary": false}'::jsonb,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX idx_trips_invite_code ON public.trips(invite_code);

-- ============================================
-- 2. PARTICIPANTS TABLE
-- ============================================
CREATE TABLE public.participants (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  trip_id uuid REFERENCES public.trips(id) ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  role text DEFAULT 'MEMBER' CHECK (role IN ('LEADER', 'MEMBER')),
  joined_at timestamptz DEFAULT now(),
  UNIQUE(trip_id, user_id)
);

CREATE INDEX idx_participants_user_id ON public.participants(user_id);
CREATE INDEX idx_participants_trip_id ON public.participants(trip_id);

-- ============================================
-- 3. SUB_GROUPS TABLE
-- ============================================
CREATE TABLE public.sub_groups (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  trip_id uuid REFERENCES public.trips(id) ON DELETE CASCADE NOT NULL,
  name text NOT NULL,
  type text DEFAULT 'CAR' CHECK (type IN ('CAR', 'ROOM', 'TEAM')),
  capacity int DEFAULT 4,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX idx_sub_groups_trip_id ON public.sub_groups(trip_id);

-- ============================================
-- 4. SUB_GROUP_MEMBERS TABLE
-- ============================================
CREATE TABLE public.sub_group_members (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  sub_group_id uuid REFERENCES public.sub_groups(id) ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  joined_at timestamptz DEFAULT now(),
  UNIQUE(sub_group_id, user_id)
);

CREATE INDEX idx_sub_group_members_user_id ON public.sub_group_members(user_id);

-- ============================================
-- 5. EXPENSES TABLE
-- ============================================
CREATE TABLE public.expenses (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  trip_id uuid REFERENCES public.trips(id) ON DELETE CASCADE NOT NULL,
  payer_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  amount decimal(12,3) NOT NULL,
  description text,
  scope text DEFAULT 'global' CHECK (scope IN ('global', 'sub_group')),
  sub_group_id uuid REFERENCES public.sub_groups(id) ON DELETE SET NULL,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX idx_expenses_trip_id ON public.expenses(trip_id);
CREATE INDEX idx_expenses_payer_id ON public.expenses(payer_id);

-- ============================================
-- 6. GEAR_ITEMS TABLE
-- ============================================
CREATE TABLE public.gear_items (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  trip_id uuid REFERENCES public.trips(id) ON DELETE CASCADE NOT NULL,
  item_name text NOT NULL,
  assigned_to uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  is_packed boolean DEFAULT false,
  sequence_id bigint DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX idx_gear_items_trip_id ON public.gear_items(trip_id);

-- ============================================
-- 7. DOCUMENTS TABLE
-- ============================================
CREATE TABLE public.documents (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  trip_id uuid REFERENCES public.trips(id) ON DELETE CASCADE NOT NULL,
  uploader_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  file_url text NOT NULL,
  file_name text NOT NULL,
  file_size bigint,
  mime_type text,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX idx_documents_trip_id ON public.documents(trip_id);

-- ============================================
-- 8. PROFILES TABLE
-- ============================================
CREATE TABLE public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name text,
  avatar_url text,
  updated_at timestamptz DEFAULT now()
);

-- ============================================
-- ENABLE RLS
-- ============================================
ALTER TABLE public.trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sub_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sub_group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gear_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- ============================================
-- SECURITY DEFINER HELPER FUNCTION
-- (Avoids infinite recursion in RLS policies)
-- ============================================
CREATE OR REPLACE FUNCTION public.is_trip_member(trip_uuid uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM participants
    WHERE trip_id = trip_uuid
    AND user_id = auth.uid()
  );
$$;

-- ============================================
-- TRIPS POLICIES
-- ============================================
CREATE POLICY "trips_insert" ON public.trips FOR INSERT TO authenticated
  WITH CHECK (true);

CREATE POLICY "trips_select" ON public.trips FOR SELECT TO authenticated
  USING (public.is_trip_member(id) OR leader_id = auth.uid());

CREATE POLICY "trips_update" ON public.trips FOR UPDATE TO authenticated
  USING (leader_id = auth.uid());

CREATE POLICY "trips_delete" ON public.trips FOR DELETE TO authenticated
  USING (leader_id = auth.uid());

-- ============================================
-- PARTICIPANTS POLICIES
-- ============================================
CREATE POLICY "participants_insert" ON public.participants FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "participants_select" ON public.participants FOR SELECT TO authenticated
  USING (public.is_trip_member(trip_id) OR user_id = auth.uid());

CREATE POLICY "participants_delete" ON public.participants FOR DELETE TO authenticated
  USING (user_id = auth.uid() OR EXISTS (SELECT 1 FROM trips WHERE id = trip_id AND leader_id = auth.uid()));

-- ============================================
-- SUB_GROUPS POLICIES
-- ============================================
CREATE POLICY "sub_groups_select" ON public.sub_groups FOR SELECT TO authenticated
  USING (public.is_trip_member(trip_id));

CREATE POLICY "sub_groups_insert" ON public.sub_groups FOR INSERT TO authenticated
  WITH CHECK (public.is_trip_member(trip_id));

CREATE POLICY "sub_groups_update" ON public.sub_groups FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM trips WHERE id = trip_id AND leader_id = auth.uid()));

CREATE POLICY "sub_groups_delete" ON public.sub_groups FOR DELETE TO authenticated
  USING (EXISTS (SELECT 1 FROM trips WHERE id = trip_id AND leader_id = auth.uid()));

-- ============================================
-- SUB_GROUP_MEMBERS POLICIES
-- ============================================
CREATE POLICY "sub_group_members_select" ON public.sub_group_members FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM sub_groups sg WHERE sg.id = sub_group_id AND public.is_trip_member(sg.trip_id)));

CREATE POLICY "sub_group_members_insert" ON public.sub_group_members FOR INSERT TO authenticated
  WITH CHECK (EXISTS (SELECT 1 FROM sub_groups sg WHERE sg.id = sub_group_id AND public.is_trip_member(sg.trip_id)));

CREATE POLICY "sub_group_members_delete" ON public.sub_group_members FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- ============================================
-- EXPENSES POLICIES
-- ============================================
CREATE POLICY "expenses_select" ON public.expenses FOR SELECT TO authenticated
  USING (public.is_trip_member(trip_id));

CREATE POLICY "expenses_insert" ON public.expenses FOR INSERT TO authenticated
  WITH CHECK (public.is_trip_member(trip_id));

CREATE POLICY "expenses_update" ON public.expenses FOR UPDATE TO authenticated
  USING (payer_id = auth.uid());

CREATE POLICY "expenses_delete" ON public.expenses FOR DELETE TO authenticated
  USING (payer_id = auth.uid() OR EXISTS (SELECT 1 FROM trips WHERE id = trip_id AND leader_id = auth.uid()));

-- ============================================
-- GEAR_ITEMS POLICIES
-- ============================================
CREATE POLICY "gear_items_select" ON public.gear_items FOR SELECT TO authenticated
  USING (public.is_trip_member(trip_id));

CREATE POLICY "gear_items_insert" ON public.gear_items FOR INSERT TO authenticated
  WITH CHECK (public.is_trip_member(trip_id));

CREATE POLICY "gear_items_update" ON public.gear_items FOR UPDATE TO authenticated
  USING (public.is_trip_member(trip_id));

CREATE POLICY "gear_items_delete" ON public.gear_items FOR DELETE TO authenticated
  USING (EXISTS (SELECT 1 FROM trips WHERE id = trip_id AND leader_id = auth.uid()));

-- ============================================
-- DOCUMENTS POLICIES
-- ============================================
CREATE POLICY "documents_select" ON public.documents FOR SELECT TO authenticated
  USING (public.is_trip_member(trip_id));

CREATE POLICY "documents_insert" ON public.documents FOR INSERT TO authenticated
  WITH CHECK (public.is_trip_member(trip_id));

CREATE POLICY "documents_delete" ON public.documents FOR DELETE TO authenticated
  USING (uploader_id = auth.uid() OR EXISTS (SELECT 1 FROM trips WHERE id = trip_id AND leader_id = auth.uid()));

-- ============================================
-- PROFILES POLICIES
-- ============================================
CREATE POLICY "profiles_select" ON public.profiles FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "profiles_update" ON public.profiles FOR UPDATE TO authenticated
  USING (id = auth.uid());

CREATE POLICY "profiles_insert" ON public.profiles FOR INSERT TO authenticated
  WITH CHECK (id = auth.uid());

-- ============================================
-- TRIGGERS
-- ============================================
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_trips_updated
  BEFORE UPDATE ON public.trips
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

CREATE TRIGGER on_gear_items_updated
  BEFORE UPDATE ON public.gear_items
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- ============================================
-- ENABLE REALTIME
-- ============================================
ALTER PUBLICATION supabase_realtime ADD TABLE public.trips;
ALTER PUBLICATION supabase_realtime ADD TABLE public.participants;
ALTER PUBLICATION supabase_realtime ADD TABLE public.sub_groups;
ALTER PUBLICATION supabase_realtime ADD TABLE public.sub_group_members;
ALTER PUBLICATION supabase_realtime ADD TABLE public.expenses;
ALTER PUBLICATION supabase_realtime ADD TABLE public.gear_items;
ALTER PUBLICATION supabase_realtime ADD TABLE public.documents;
