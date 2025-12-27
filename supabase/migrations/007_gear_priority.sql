-- ============================================
-- SAFAR: Gear Priority Migration
-- Adds: is_high_priority to gear_items
-- ============================================

ALTER TABLE public.gear_items 
ADD COLUMN IF NOT EXISTS is_high_priority boolean DEFAULT false;

-- Correct existing data (optional, but good practice)
UPDATE public.gear_items SET is_high_priority = false WHERE is_high_priority IS NULL;
