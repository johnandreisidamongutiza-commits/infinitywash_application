// Authenticated password change endpoint with credential re-check and a
// server-side per-account limit. Deploy with `supabase functions deploy change-password`.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}
const MAX_CHANGES_PER_HOUR = 3
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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS })
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405)

  const authorization = req.headers.get("Authorization") ?? ""
  const jwt = authorization.replace(/^Bearer\s+/i, "")
  const url = Deno.env.get("SUPABASE_URL")
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")
  if (!jwt || !url || !serviceKey || !anonKey) {
    return json({ error: "Authentication required." }, 401)
  }

  let body: { email?: string; current_password?: string; new_password?: string }
  try {
    body = await req.json()
  } catch {
    return json({ error: "Invalid request." }, 400)
  }
  const email = (body.email ?? "").trim().toLowerCase()
  const currentPassword = body.current_password ?? ""
  const newPassword = body.new_password ?? ""
  if (!email || !currentPassword) {
    return json({ error: "Enter your current password and a new password." }, 400)
  }
  if (currentPassword === newPassword) {
    return json({ error: "New password must be different from current password." }, 400)
  }
  const passwordError = validateNewPassword(newPassword)
  if (passwordError) {
    return json({ error: passwordError }, 400)
  }

  const admin = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } })
  const { data: authData, error: authError } = await admin.auth.getUser(jwt)
  const user = authData.user
  if (authError || !user || user.email?.toLowerCase() !== email) {
    return json({ error: "Your session is invalid. Please sign in again." }, 401)
  }

  // Verify the current password independently; possession of a long-lived
  // session token alone must not be enough to rotate account credentials.
  const verifier = createClient(url, anonKey, { auth: { autoRefreshToken: false, persistSession: false } })
  const { data: verified, error: verifyError } = await verifier.auth.signInWithPassword({
    email,
    password: currentPassword,
  })
  if (verifyError || verified.user?.id !== user.id) {
    return json({ error: "Current password is incorrect." }, 401)
  }

  const since = new Date(Date.now() - 60 * 60 * 1000).toISOString()
  await admin
    .from("password_change_attempts")
    .delete()
    .eq("user_id", user.id)
    .lt("created_at", new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString())
  const { count, error: countError } = await admin
    .from("password_change_attempts")
    .select("id", { count: "exact", head: true })
    .eq("user_id", user.id)
    .gte("created_at", since)
  if (countError) {
    console.error("[change-password] rate-limit lookup failed", countError)
    return json({ error: "Password service is temporarily unavailable." }, 503)
  }
  if ((count ?? 0) >= MAX_CHANGES_PER_HOUR) {
    return json({ error: "Too many password changes. Please try again later." }, 429)
  }

  const { error: logError } = await admin.from("password_change_attempts").insert({ user_id: user.id })
  if (logError) {
    console.error("[change-password] attempt log failed", logError)
    return json({ error: "Password service is temporarily unavailable." }, 503)
  }
  const { error: updateError } = await admin.auth.admin.updateUserById(user.id, { password: newPassword })
  if (updateError) {
    console.error("[change-password] password update failed", updateError)
    return json({ error: "Password change failed. Please try again." }, 500)
  }
  return json({ ok: true })
})
