-- Payment tracking for Thawani integration
-- ==========================================

-- Add payment tracking columns to settlements
ALTER TABLE settlements
ADD COLUMN IF NOT EXISTS payment_method TEXT DEFAULT 'manual',
ADD COLUMN IF NOT EXISTS payment_reference TEXT,
ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'completed';

-- Index for payment lookups
CREATE INDEX IF NOT EXISTS idx_settlements_payment_ref
    ON settlements(payment_reference)
    WHERE payment_reference IS NOT NULL;

COMMENT ON COLUMN settlements.payment_method IS 'Payment method: manual, thawani';
COMMENT ON COLUMN settlements.payment_reference IS 'External payment reference (e.g. Thawani session ID)';
COMMENT ON COLUMN settlements.payment_status IS 'Payment status: pending, completed, failed, cancelled';
