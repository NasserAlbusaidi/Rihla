# Push Notifications Setup

Rihla stores device tokens in Supabase, but delivery still requires manual project setup outside the repo.

## Required Secrets
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `FCM_SERVER_KEY`

Set these on the Supabase Edge Function used by `supabase/functions/send-notification`.

## Required Database Objects
- Apply migrations through `026_fcm_tokens.sql`.
- Deploy the `send-notification` edge function.

## Required Webhooks
Create database webhooks in Supabase for:
- `public.expenses` on `INSERT`
- `public.settlements` on `INSERT`

Both webhooks should POST to the deployed `send-notification` function.

## Payload Expectations
The edge function expects:
- `table`
- `type`
- `record`

The `record` must include:
- `trip_id`
- `payer_participant_id`
- `amount`
- `currency`

## Notes
- Notification opt-in is controlled in app settings and stored in `SharedPreferences`.
- If the device permission is denied, the app will keep notifications off and surface that state in settings.
