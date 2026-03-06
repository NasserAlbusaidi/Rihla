-- Add currency column to trips table
ALTER TABLE trips ADD COLUMN IF NOT EXISTS currency text NOT NULL DEFAULT 'OMR';

-- Add comment for documentation
COMMENT ON COLUMN trips.currency IS 'ISO 4217 currency code for this trip';
