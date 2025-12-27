-- ============================================
-- 018: Auto-Create Profile on User Signup
-- ============================================
-- This migration adds a trigger to automatically create a profile
-- when a new user signs up, using their email username as display_name.

-- Function to create profile on new user
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name)
  VALUES (
    NEW.id,
    COALESCE(
      NEW.raw_user_meta_data->>'full_name',
      NEW.raw_user_meta_data->>'name',
      SPLIT_PART(NEW.email, '@', 1)
    )
  )
  ON CONFLICT (id) DO UPDATE SET
    display_name = COALESCE(
      profiles.display_name,
      EXCLUDED.display_name
    );
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger on auth.users
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- Backfill existing users without profiles
INSERT INTO public.profiles (id, display_name)
SELECT 
  id,
  COALESCE(
    raw_user_meta_data->>'full_name',
    raw_user_meta_data->>'name', 
    SPLIT_PART(email, '@', 1)
  )
FROM auth.users
WHERE id NOT IN (SELECT id FROM public.profiles)
ON CONFLICT (id) DO NOTHING;

-- Also update profiles with null display_name
UPDATE public.profiles p
SET display_name = COALESCE(
  u.raw_user_meta_data->>'full_name',
  u.raw_user_meta_data->>'name',
  SPLIT_PART(u.email, '@', 1)
)
FROM auth.users u
WHERE p.id = u.id AND p.display_name IS NULL;

COMMENT ON FUNCTION public.handle_new_user IS 
  'Automatically creates a profile with display_name from email when a user signs up.';
