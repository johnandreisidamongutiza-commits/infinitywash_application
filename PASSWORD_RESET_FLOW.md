# Password Reset — Server-Side Flow

The entire forgot-password flow runs inside the `password-reset` Edge Function.
The Flutter app only relays user input; it never sees reset codes, their hashes,
SMTP credentials, or the password-reset decision logic.

## Why

Previously the app held a Gmail app password in `lib/services/smtp_service.dart`
and verified reset codes in Dart against rows it read directly from
`password_reset_tokens`. Anyone could extract the credential from the APK and
send mail as the shop, and the code check/attempt counting was trivially
bypassed by talking to the database directly (or broke entirely once RLS was
tightened).

## Components

| Piece | Role |
| --- | --- |
| `supabase/functions/password-reset/index.ts` | Single endpoint: `request`, `verify`, `reset`. Generates the 6-char code, stores only its SHA-256 hash, enforces per-email send limits (3/hour) and per-token attempt limits (5), sends the email via SMTP secrets, and performs the admin password update. |
| `supabase/migrations/20261002_password_reset_hardening.sql` | Ensures `password_reset_tokens` exists, enables RLS with **no** client policies, revokes client grants, drops the legacy `reset_user_password` RPC, adds lookup indexes. |
| `supabase/migrations/20261002_password_reset_hardening_rollback.sql` | Emergency rollback to the old insecure flow. Do not deploy unless absolutely required. |
| `lib/services/password_reset_service.dart` | Thin client: `requestPasswordReset`, `verifyResetCode`, `resetPassword`, `resendResetCode`. Surfaces server error messages verbatim. |
| `lib/screens/forgot_password_screen.dart` | 4-step UI (email → OTP → new password → success). No local crypto, no token ids. |

## Deploy checklist

```bash
# 1. Apply the migration (locks the table, removes the old RPC)
supabase db push

# 2. Set the SMTP secrets (never in the app binary)
supabase secrets set \
  SMTP_HOST=smtp.gmail.com \
  SMTP_PORT=587 \
  SMTP_USER=your.address@gmail.com \
  SMTP_PASS="16-char Gmail app password" \
  SMTP_FROM="InfinityWash <your.address@gmail.com>" \
  SMTP_FROM_NAME="InfinityWash"

# 3. Deploy the function
supabase functions deploy password-reset
```

Notes:

- `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected by the platform
  automatically; do not set them yourself.
- Keep JWT verification enabled (the default). `functions.invoke` sends the
  anon key, which is enough.
- If SMTP secrets are missing, the function still creates the token but the
  code is **not** delivered and nothing is echoed to the client — check the
  function logs for `[password-reset] SMTP secrets not set`.

## Gmail specifics

1. Enable 2-Factor Authentication on the Google account.
2. Create an **App Password** (Google Account → Security → App passwords).
3. Use that 16-character password as `SMTP_PASS` — never your real password.
4. Gmail caps you at ~500 mails/day; the hourly rate limit keeps you well under.

## Rotation / incident response

If `SMTP_PASS` ever leaks (e.g. an old APK is still in circulation):

1. Revoke the app password in the Google account.
2. `supabase secrets set SMTP_PASS="<new app password>"`.
3. `supabase functions deploy password-reset` (secrets apply on redeploy).
4. Invalidate outstanding tokens:
   `update public.password_reset_tokens set used = true where used = false;`

## Verifying the flow end-to-end

1. In the app: Forgot password → enter an existing email → **Send code**.
2. The inbox receives the 6-character code within seconds.
3. Enter the code → **Verify Code** → set a new password.
4. Log in with the new password.

Deliberately broken paths (all should show the server's message):

- Unknown email → "No account found with this email address…"
- Wrong code 5× → attempt counter exhausts, token consumed.
- 4th code request within an hour → 429 "Too many code requests."
- Code older than 15 minutes → "Reset code has expired…"
