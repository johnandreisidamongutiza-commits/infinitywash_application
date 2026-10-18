# Customer registration email OTP setup

The app now collects registration details in steps and calls the
`customer-registration-otp` Edge Function. The function sends the OTP over
SMTP, keeps only the code hash, and creates/confirms the Supabase Auth user
only after a valid code is entered. It does not store the password while the
registration is pending.

## One-time Supabase setup

1. Run `supabase/migrations/20261018_customer_registration_otp.sql` in the
   Supabase SQL Editor (or deploy migrations with the Supabase CLI).
2. Configure SMTP secrets for the Edge Function. For the Gmail SMTP sender,
   use `smtp.gmail.com`, port `465`, username `infinitywash001@gmail.com`,
   an App Password generated for that Google account, and
   `SMTP_FROM="Infinity Wash <infinitywash001@gmail.com>"`.
3. Deploy `supabase/functions/customer-registration-otp`.

Set secrets in the Supabase project/server secret manager, never in Flutter or
Git. The Gmail App Password previously pasted into chat should be revoked and
replaced before setup. The existing `password-reset` function uses its own
SMTP secrets; configuring this function does not automatically change those.

Add the SMTP values in Supabase's Edge Function secrets (or use the CLI's
secret command from a trusted local terminal). Enter the replacement App
Password directly there; do not paste it into a command that may be saved in
shell history.

The pending-registration table has RLS enabled and grants no client access.
The Edge Function uses the service role key injected by Supabase. OTPs expire
after 15 minutes, resend is limited to 3 per email per hour, and each code has
at most 5 verification attempts. Pending PII is removed after its rate-limit
window expires.

## Google sign-in setup

The login screen includes **Continue with Google**. Add
`com.example.infinitywash://login-callback/` to Supabase Authentication → URL
Configuration → Redirect URLs. The same callback scheme is registered in the
Android manifest and iOS URL types. Google sign-in creates/authenticates the
user first; the app then requires phone, address, and legal consent before
routing to the customer screens.

The Google OAuth client ID and secret must be configured in Supabase's Google
provider settings, and Google's Authorized redirect URI must be the Supabase
callback shown on that provider page. Do not put the Google client secret in
the Flutter app.
