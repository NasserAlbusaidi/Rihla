-- ============================================
-- 019: Fix Settlements Table Schema
-- ============================================
-- Adds missing columns for settlements

-- Add currency column
ALTER TABLE public.settlements 
  ADD COLUMN IF NOT EXISTS currency text DEFAULT 'OMR';

-- Add settled_at column
ALTER TABLE public.settlements 
  ADD COLUMN IF NOT EXISTS settled_at timestamptz DEFAULT now();

-- Add soft delete columns
ALTER TABLE public.settlements 
  ADD COLUMN IF NOT EXISTS is_deleted boolean DEFAULT false;

ALTER TABLE public.settlements 
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz;

-- Add participant ID columns if they don't exist
ALTER TABLE public.settlements 
  ADD COLUMN IF NOT EXISTS payer_participant_id uuid REFERENCES public.participants(id) ON DELETE SET NULL;

ALTER TABLE public.settlements 
  ADD COLUMN IF NOT EXISTS recipient_participant_id uuid REFERENCES public.participants(id) ON DELETE SET NULL;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_settlements_payer_participant ON public.settlements(payer_participant_id);
CREATE INDEX IF NOT EXISTS idx_settlements_recipient_participant ON public.settlements(recipient_participant_id);
CREATE INDEX IF NOT EXISTS idx_settlements_is_deleted ON public.settlements(is_deleted);
