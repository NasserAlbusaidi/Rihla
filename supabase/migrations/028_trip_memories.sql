-- Trip Memories: shared photo timeline per trip
-- ================================================

-- Table for memory metadata
CREATE TABLE IF NOT EXISTS trip_memories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    uploaded_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    storage_path TEXT NOT NULL,
    caption TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX idx_trip_memories_trip_id ON trip_memories(trip_id);
CREATE INDEX idx_trip_memories_created_at ON trip_memories(created_at DESC);

-- RLS
ALTER TABLE trip_memories ENABLE ROW LEVEL SECURITY;

-- Trip members can view all memories for their trips
CREATE POLICY "trip_members_can_view_memories"
    ON trip_memories FOR SELECT
    USING (is_trip_member(trip_id));

-- Trip members can insert memories
CREATE POLICY "trip_members_can_insert_memories"
    ON trip_memories FOR INSERT
    WITH CHECK (is_trip_member(trip_id) AND uploaded_by = auth.uid());

-- Users can delete their own memories
CREATE POLICY "users_can_delete_own_memories"
    ON trip_memories FOR DELETE
    USING (uploaded_by = auth.uid());

-- Storage bucket for trip memory photos
INSERT INTO storage.buckets (id, name, public)
VALUES ('trip-memories', 'trip-memories', false)
ON CONFLICT (id) DO NOTHING;

-- Storage policies: trip members can upload/view/delete photos
CREATE POLICY "trip_memory_upload"
    ON storage.objects FOR INSERT
    WITH CHECK (
        bucket_id = 'trip-memories'
        AND auth.uid() IS NOT NULL
    );

CREATE POLICY "trip_memory_view"
    ON storage.objects FOR SELECT
    USING (
        bucket_id = 'trip-memories'
        AND auth.uid() IS NOT NULL
    );

CREATE POLICY "trip_memory_delete"
    ON storage.objects FOR DELETE
    USING (
        bucket_id = 'trip-memories'
        AND auth.uid() IS NOT NULL
    );
