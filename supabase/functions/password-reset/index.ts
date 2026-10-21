// Supabase Edge Function: password-reset
//
// Handles the ENTIRE forgot-password flow server-side:
//   action = "request" -> rate-limit, generate code, store hash, email the code
//   action = "verify"  -> check email + code, consume attempts, return ok
//   action = "reset"   -> re-verify code, then update the auth password (admin)
//
// Security properties:
//   - The 6-char code is generated, hashed (SHA-256) and compared ONLY here.
//     Clients never see code_hash and can never verify offline.
//   - SMTP credentials live in function secrets, never in the app binary.
//   - Password updates go through the service-role Admin API; the anon key
//     cannot read password_reset_tokens (RLS denies all client roles).
//   - Per-email send rate limit (3/hour) and per-token attempt limit (5).
//
// Deploy:
//   supabase functions deploy password-reset
//   supabase secrets set SMTP_HOST=smtp.gmail.com SMTP_PORT=465 \
//     SMTP_USER=you@gmail.com SMTP_PASS=<app-password> \
//     SMTP_FROM="InfinityWash <you@gmail.com>"
//
// The function relies on SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY which the
// platform injects automatically. JWT verification stays enabled (default),
// so callers must pass a valid anon/authenticated key (functions.invoke does).

import nodemailer from "https://esm.sh/nodemailer@6.9.16"

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}

const CODE_TTL_MINUTES = 15
const MAX_SENDS_PER_HOUR = 3
const MAX_VERIFY_ATTEMPTS = 5
const MIN_PASSWORD_LENGTH = 8
const MAX_PASSWORD_LENGTH = 72

function validateNewPassword(password: string): string | null {
  if (password.length < MIN_PASSWORD_LENGTH) {
    return `Password must be at least ${MIN_PASSWORD_LENGTH} characters long.`
  }
  if (password.length > MAX_PASSWORD_LENGTH) {
    return `Password must be no more than ${MAX_PASSWORD_LENGTH} characters long.`
  }
  if (
    !/[A-Z]/.test(password) ||
    !/[a-z]/.test(password) ||
    !/[0-9]/.test(password) ||
    !/[^A-Za-z0-9]/.test(password)
  ) {
    return "Password must include an uppercase letter, a lowercase letter, a number, and a symbol."
  }
  return null
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  })
}

function fail(error: string, status = 400): Response {
  return json({ error }, status)
}

// 3 random letters + 3 random digits, matching the legacy format.
function generateCode(): string {
  const letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
  const digits = "0123456789"
  const pick = (alphabet: string): string => {
    const bytes = new Uint32Array(1)
    crypto.getRandomValues(bytes)
    return alphabet[bytes[0] % alphabet.length]
  }
  let code = ""
  for (let i = 0; i < 3; i++) code += pick(letters)
  for (let i = 0; i < 3; i++) code += pick(digits)
  return code
}

async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(input),
  )
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")
}

// Length-independent comparison so timing leaks nothing about the hash.
function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return diff === 0
}

function createAdminClient() {
  const url = Deno.env.get("SUPABASE_URL")
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
  if (!url || !serviceKey) {
    throw new Error("Function is missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY")
  }
  // Lazy import keeps startup cheap; service role bypasses RLS by design.
  return import("https://esm.sh/@supabase/supabase-js@2").then(
    ({ createClient }) =>
      createClient(url, serviceKey, {
        auth: { autoRefreshToken: false, persistSession: false },
      }),
  )
}

async function sendResetEmail(
  to: string,
  code: string,
  name: string,
): Promise<void> {
  const host = Deno.env.get("SMTP_HOST") ?? "smtp.gmail.com"
  // InfinityWashSMTP is the existing app-password secret in this project.
  const user = Deno.env.get("SMTP_USER") ?? "infinitywash001@gmail.com"
  const pass = Deno.env.get("SMTP_PASS") ?? Deno.env.get("InfinityWashSMTP")

  if (!host || !user || !pass) {
    throw new Error("Email delivery is not configured (Gmail App Password secret is missing)")
  }

  // Supabase blocks outbound SMTP on ports 25 and 587. Gmail's implicit TLS
  // endpoint on 465 is supported; an HTTPS email API is another option.
  const port = Number(Deno.env.get("SMTP_PORT") ?? "465")
  if (!Number.isInteger(port) || port < 1 || port > 65535 || port === 25 || port === 587) {
    throw new Error("SMTP_PORT must be 465; Supabase blocks SMTP ports 25 and 587")
  }
  const from = Deno.env.get("SMTP_FROM") ?? `InfinityWash <${user}>`
  const senderName = Deno.env.get("SMTP_FROM_NAME") ?? "InfinityWash"

  const transporter = nodemailer.createTransport({
    host,
    port,
    secure: port === 465,
    auth: { user, pass },
  })

  const year = new Date().getFullYear()
  await transporter.sendMail({
    from,
    to,
    subject: "Password Reset Code - InfinityWash",
    html: `<!DOCTYPE html>
<html>
  <head><meta charset="utf-8" /></head>
  <body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333; margin:0; padding:0;">
    <div style="max-width:600px;margin:0 auto;padding:20px;">
      <div style="background:#0D3B66;color:white;padding:30px;text-align:center;border-radius:10px 10px 0 0;">
        <h1 style="margin:0;">&#128272; Password Reset Request</h1>
      </div>
      <div style="background:#f9f9f9;padding:30px;border-radius:0 0 10px 10px;">
        <p>Hello ${name || "there"},</p>
        <p>You requested to reset your password for your ${senderName} account.</p>
        <p><strong>Your verification code is:</strong></p>
        <div style="background:white;border:2px solid #2196F3;border-radius:10px;padding:20px;margin:20px 0;text-align:center;">
          <span style="font-size:36px;font-weight:bold;letter-spacing:8px;color:#2196F3;font-family:'Courier New',monospace;">${code}</span>
        </div>
        <div style="background:#fff3cd;border-left:4px solid #ffc107;padding:15px;margin:20px 0;">
          &#9200; <strong>This code expires in ${CODE_TTL_MINUTES} minutes</strong>
        </div>
        <p>Enter this code in the app to continue with your password reset.</p>
        <ul>
          <li>This code can only be used once</li>
          <li>Don't share this code with anyone</li>
          <li>If you didn't request this, you can safely ignore this email</li>
        </ul>
        <hr style="border:none;border-top:1px solid #ddd;margin:20px 0;" />
        <p style="color:#666;font-size:12px;">&copy; ${year} ${senderName}. All rights reserved.</p>
      </div>
    </div>
  </body>
</html>`,
  })
}

// Resolve the auth user id from the profiles table (service role bypasses RLS).
async function findAuthUserId(
  admin: Awaited<ReturnType<typeof createAdminClient>>,
  email: string,
): Promise<string | null> {
  const { data: profile } = await admin
    .from("profiles")
    .select("supabase_user_id, status")
    .ilike("email", email)
    .limit(1)
    .maybeSingle()

  if (!profile) return null
  if (profile.status && String(profile.status).toLowerCase() !== "active") {
    throw new Error("This account is not active. Please contact support.")
  }
  return (profile.supabase_user_id as string) ?? null
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS })
  }
  if (req.method !== "POST") {
    return fail("Method not allowed", 405)
  }

  let body: { action?: string; email?: string; code?: string; new_password?: string; captcha_token?: string }
  try {
    body = await req.json()
  } catch {
    return fail("Invalid JSON body")
  }

  const action = body.action
  const email = (body.email ?? "").trim().toLowerCase()
  const code = (body.code ?? "").trim()

  if (!email || !email.includes("@")) {
    return fail("A valid email address is required")
  }

  let admin
  try {
    admin = await createAdminClient()
  } catch (err) {
    console.error("[password-reset] admin client error:", err)
    return fail("Server configuration error", 500)
  }

  try {
    if (action === "request") {
      const captchaToken = (body.captcha_token ?? "").trim()
      const turnstileSecret = Deno.env.get("TURNSTILE_SECRET_KEY")
      if (!turnstileSecret) {
        console.error("[password-reset] TURNSTILE_SECRET_KEY is not configured")
        return fail("Security check is unavailable. Please try again later.", 503)
      }
      if (!captchaToken) return fail("Please complete the security check.", 400)
      const captchaResponse = await fetch(
        "https://challenges.cloudflare.com/turnstile/v0/siteverify",
        {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body: new URLSearchParams({
            secret: turnstileSecret,
            response: captchaToken,
          }),
        },
      )
      const captchaResult = await captchaResponse.json()
      const expectedHostname = new URL(Deno.env.get("SUPABASE_URL")!).hostname
      if (
        !captchaResponse.ok ||
        captchaResult.success !== true ||
        captchaResult.hostname !== expectedHostname ||
        captchaResult.action !== "password_reset"
      ) {
        return fail("Security check failed or expired. Please try again.", 400)
      }

      // 1. Profile + status checks.
      const { data: profile } = await admin
        .from("profiles")
        .select("email, supabase_user_id, first_name, last_name, status")
        .ilike("email", email)
        .limit(1)
        .maybeSingle()

      if (!profile) {
        // Same shape as success paths that need it; do not leak whether the
        // account exists beyond this message (kept for UX parity).
        return fail("No account found with this email address. Please check your email or sign up.")
      }
      if (profile.status && String(profile.status).toLowerCase() !== "active") {
        return fail("This account is not active. Please contact support.")
      }

      // 2. Server-side per-email rate limit: tokens created in the last hour.
      const since = new Date(Date.now() - 60 * 60 * 1000).toISOString()
      const { count } = await admin
        .from("password_reset_tokens")
        .select("id", { count: "exact", head: true })
        .ilike("email", email)
        .eq("email_sent", true)
        .gte("created_at", since)

      if ((count ?? 0) >= MAX_SENDS_PER_HOUR) {
        const { data: oldestRequest } = await admin
          .from("password_reset_tokens")
          .select("created_at")
          .ilike("email", email)
          .eq("email_sent", true)
          .gte("created_at", since)
          .order("created_at", { ascending: true })
          .limit(1)
          .maybeSingle()
        const retryAt = oldestRequest
          ? new Date(oldestRequest.created_at).getTime() + 60 * 60 * 1000
          : Date.now() + 60 * 1000
        const waitMinutes = Math.max(1, Math.ceil((retryAt - Date.now()) / 60000))
        return fail(
          `You've reached the limit of ${MAX_SENDS_PER_HOUR} code requests in one hour. Please wait about ${waitMinutes} minute${waitMinutes == 1 ? "" : "s"} and try again.`,
          429,
        )
      }

      // 3. Invalidate previous unused codes for this email.
      await admin
        .from("password_reset_tokens")
        .update({ used: true })
        .ilike("email", email)
        .eq("used", false)

      // 4. Generate + store the code (hash only).
      const code = generateCode()
      const codeHash = await sha256Hex(code)
      const now = new Date()
      const expiresAt = new Date(now.getTime() + CODE_TTL_MINUTES * 60 * 1000)

      const { data: insertedToken, error: insertError } = await admin
        .from("password_reset_tokens")
        .insert({
          email: profile.email,
          code_hash: codeHash,
          expires_at: expiresAt.toISOString(),
          sent_at: now.toISOString(),
          created_at: now.toISOString(),
          email_sent: false,
          attempts: 0,
          used: false,
        })
        .select("id")
        .single()
      if (insertError) throw insertError

      // 5. Deliver the code.
      const fullName =
        [profile.first_name, profile.last_name].filter(Boolean).join(" ")
      try {
        await sendResetEmail(profile.email, code, fullName)
      } catch (mailError) {
        // A code must never remain usable when its email was not accepted.
        await admin
          .from("password_reset_tokens")
          .update({ used: true, email_sent: false })
          .eq("id", insertedToken?.id ?? "")
        const mailDetails = mailError as {
          code?: unknown
          responseCode?: unknown
          command?: unknown
        }
        const errorCode = typeof mailDetails?.code === "string"
          ? mailDetails.code
          : "UNKNOWN"
        const responseCode = typeof mailDetails?.responseCode === "number"
          ? mailDetails.responseCode
          : null
        const setupError = mailError instanceof Error ? mailError.message : ""
        console.error("[password-reset] email delivery failed:", JSON.stringify({
          code: errorCode,
          responseCode,
          command: typeof mailDetails?.command === "string"
            ? mailDetails.command
            : null,
        }))
        const deliveryMessage = setupError.includes("not configured") || setupError.includes("SMTP_PORT")
          ? "Email delivery is not configured. Check the password-reset SMTP secrets and use port 465."
          : errorCode === "EAUTH" || responseCode === 535 || responseCode === 534
          ? "Gmail rejected the SMTP login. Update the InfinityWashSMTP secret with a valid Google App Password for the sender account."
          : ["ETIMEDOUT", "ESOCKET", "ECONNECTION", "ECONNRESET"].includes(errorCode)
          ? "The app could not connect to Gmail SMTP on port 465. Check the SMTP connection and try again."
          : "Gmail could not accept the verification email. Check the password-reset function logs or try again later."
        return fail(
          deliveryMessage,
          503,
        )
      }

      // Count only emails that Gmail accepted, never failed attempts.
      const { error: deliveryMarkError } = await admin
        .from("password_reset_tokens")
        .update({ email_sent: true, sent_at: new Date().toISOString() })
        .eq("id", insertedToken.id)
      if (deliveryMarkError) {
        // The email was accepted already; preserve success for the user while
        // recording the database problem for operators to investigate.
        console.error("[password-reset] email delivered but status update failed:", deliveryMarkError.code)
      }

      const sentThisHour = (count ?? 0) + 1
      return json({
        ok: true,
        email: profile.email,
        attempts_left: Math.max(0, MAX_SENDS_PER_HOUR - sentThisHour),
      })
    }

    if (action === "verify") {
      if (!code) return fail("The verification code is required")

      const { data: token } = await admin
        .from("password_reset_tokens")
        .select("id, code_hash, expires_at, attempts, used")
        .ilike("email", email)
        .eq("used", false)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle()

      if (!token) {
        return fail("No valid reset request found. Please request a new code.")
      }
      if (new Date() > new Date(token.expires_at)) {
        return fail("Reset code has expired. Please request a new code.")
      }
      if (token.attempts >= MAX_VERIFY_ATTEMPTS) {
        await admin.from("password_reset_tokens").update({ used: true }).eq("id", token.id)
        return fail("Too many failed attempts. Please request a new code.", 429)
      }

      const matches = constantTimeEqual(
        await sha256Hex(code),
        token.code_hash as string,
      )
      if (!matches) {
        await admin
          .from("password_reset_tokens")
          .update({ attempts: token.attempts + 1 })
          .eq("id", token.id)
        const remaining = MAX_VERIFY_ATTEMPTS - (token.attempts + 1)
        return fail(
          remaining > 0
            ? `Invalid code. ${remaining} attempts remaining.`
            : "Invalid code. Too many attempts. Please request a new code.",
          remaining > 0 ? 400 : 429,
        )
      }

      return json({ ok: true })
    }

    if (action === "reset") {
      if (!code) return fail("The verification code is required")
      const newPassword = body.new_password ?? ""
      const passwordError = validateNewPassword(newPassword)
      if (passwordError) return fail(passwordError)

      // Re-validate the code fully — the password step never trusts the client.
      const { data: token } = await admin
        .from("password_reset_tokens")
        .select("id, code_hash, expires_at, attempts, used, email")
        .ilike("email", email)
        .eq("used", false)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle()

      if (!token) {
        return fail("No valid reset request found. Please request a new code.")
      }
      if (new Date() > new Date(token.expires_at)) {
        return fail("This reset code has expired. Please request a new one.")
      }
      if (token.attempts >= MAX_VERIFY_ATTEMPTS) {
        await admin.from("password_reset_tokens").update({ used: true }).eq("id", token.id)
        return fail("Too many failed attempts. Please request a new code.", 429)
      }

      const matches = constantTimeEqual(
        await sha256Hex(code),
        token.code_hash as string,
      )
      if (!matches) {
        await admin
          .from("password_reset_tokens")
          .update({ attempts: token.attempts + 1 })
          .eq("id", token.id)
        return fail("Invalid or expired reset code. Please try again.")
      }

      const userId = await findAuthUserId(admin, token.email as string)
      if (!userId) {
        return fail(
          "User account not found in Auth system. Please contact support.",
          404,
        )
      }

      const { error: updateError } = await admin.auth.admin.updateUserById(userId, {
        password: newPassword,
      })
      if (updateError) {
        console.error("[password-reset] updateUserById failed:", updateError)
        return fail("Password reset failed. Please try again.", 500)
      }

      // Single-use enforcement.
      await admin
        .from("password_reset_tokens")
        .update({ used: true })
        .eq("id", token.id)

      return json({ ok: true, message: "Password reset successfully" })
    }

    return fail("Unknown action. Expected request, verify or reset.")
  } catch (err) {
    console.error("[password-reset] unhandled error:", err)
    return fail("Internal server error", 500)
  }
})
