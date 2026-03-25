-- Add receipt_path column to expenses table
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS receipt_path text;
COMMENT ON COLUMN expenses.receipt_path IS 'Storage path to receipt image in receipts bucket';

-- Create private receipts bucket (not public)
INSERT INTO storage.buckets (id, name, public)
VALUES ('receipts', 'receipts', false)
ON CONFLICT (id) DO NOTHING;

-- RLS: Only trip participants can upload receipts for their trip
CREATE POLICY "Trip participants can upload receipts"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'receipts'
  AND EXISTS (
    SELECT 1 FROM participants p
    WHERE p.user_id = auth.uid()
    AND p.trip_id = ((storage.foldername(name))[1])::uuid
  )
);

-- RLS: Only trip participants can view receipts for their trip
CREATE POLICY "Trip participants can view receipts"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'receipts'
  AND EXISTS (
    SELECT 1 FROM participants p
    WHERE p.user_id = auth.uid()
    AND p.trip_id = ((storage.foldername(name))[1])::uuid
  )
);

-- RLS: Only the uploader can delete their receipts
CREATE POLICY "Users can delete own receipts"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'receipts'
  AND owner_id = auth.uid()::text
);
