import nodemailer from "https://esm.sh/nodemailer@6.9.16"

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}
const TTL_MINUTES = 15
const MAX_SENDS = 3
const MAX_ATTEMPTS = 5

function reply(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...headers, "Content-Type": "application/json" },
  })
}
function fail(error: string, status = 400) { return reply({ error }, status) }
async function hash(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value))
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("")
}
function constantEqual(a: string, b: string) {
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return diff === 0
}
function newCode() {
  const bytes = new Uint32Array(1)
  crypto.getRandomValues(bytes)
  return String(bytes[0] % 1_000_000).padStart(6, "0")
}
async function adminClient() {
  const url = Deno.env.get("SUPABASE_URL")
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
  if (!url || !key) throw new Error("Missing Supabase server configuration")
  const { createClient } = await import("https://esm.sh/@supabase/supabase-js@2")
  return createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } })
}
async function findUserByEmail(admin: Awaited<ReturnType<typeof adminClient>>, email: string) {
  // Supabase paginates Auth users; search every page so duplicate emails are
  // handled correctly even after the project grows beyond the first 1,000.
  for (let page = 1; ; page++) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 1000 })
    if (error) throw error
    const match = data.users.find((user) => user.email?.toLowerCase() === email)
    if (match) return match
    if (data.users.length < 1000) return null
  }
}
async function sendOtp(email: string, code: string, firstName: string) {
  const host = Deno.env.get("SMTP_HOST")
  const user = Deno.env.get("SMTP_USER")
  const pass = Deno.env.get("SMTP_PASS")
  if (!host || !user || !pass) throw new Error("Registration email is not configured yet")
  const port = Number(Deno.env.get("SMTP_PORT") ?? "465")
  const from = Deno.env.get("SMTP_FROM") ?? `Infinity Wash <${user}>`
  const sender = Deno.env.get("SMTP_FROM_NAME") ?? "Infinity Wash"
  const transport = nodemailer.createTransport({ host, port, secure: port === 465, auth: { user, pass } })
  await transport.sendMail({
    from, to: email, subject: "Verify your Infinity Wash account",
    html: `<div style="font-family:Arial,sans-serif;max-width:560px;margin:auto;padding:28px;color:#172033"><h2>Verify your email</h2><p>Hello ${escapeHtml(firstName || "there")}, enter this code in Infinity Wash to finish creating your account:</p><p style="font-size:34px;font-weight:bold;letter-spacing:8px;color:#2563eb;text-align:center">${code}</p><p>This code expires in ${TTL_MINUTES} minutes and can only be used once.</p><p>If you did not start this registration, ignore this email.</p></div>`,
  })
}
function escapeHtml(value: string) { return value.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!) }

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers })
  if (req.method !== "POST") return fail("Method not allowed", 405)
  let body: Record<string, unknown>
  try { body = await req.json() } catch { return fail("Invalid request") }
  const action = String(body.action ?? "")
  const email = String(body.email ?? "").trim().toLowerCase()
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return fail("Enter a valid email address")
  try {
    const admin = await adminClient()
    if (action === "check") {
      const existingUser = await findUserByEmail(admin, email)
      if (existingUser) {
        const { data: profile } = await admin.from("profiles")
          .select("role, status, first_name, last_name, phone, address")
          .eq("supabase_user_id", existingUser.id)
          .maybeSingle()

        const isProfileComplete = profile &&
          profile.role === "customer" &&
          profile.status === "active" &&
          Boolean(profile.first_name?.trim()) &&
          Boolean(profile.last_name?.trim()) &&
          Boolean(profile.phone?.trim()) &&
          Boolean(profile.address?.trim())

        const isGoogle = existingUser.app_metadata?.provider === "google" ||
          (Array.isArray(existingUser.app_metadata?.providers) && existingUser.app_metadata.providers.includes("google"))

        if (!isProfileComplete) {
          return reply({ status: "incomplete_profile", is_google: isGoogle })
        }

        if (existingUser.email_confirmed_at) return reply({ status: "registered", is_google: isGoogle })
      }
      const { data: pending, error } = await admin.from("pending_customer_registrations")
        .select("email, created_at")
        .eq("email", email)
        .maybeSingle()
      if (error) throw error
      if (pending && Date.now() - new Date(pending.created_at).getTime() < 60 * 60_000) {
        return reply({ status: "pending" })
      }
      return reply({ status: "new" })
    }
    if (action === "start" || action === "resend") {
      await admin.from("pending_customer_registrations")
        .delete()
        .lt("created_at", new Date(Date.now() - 60 * 60_000).toISOString())
      let data = body.registration_data as Record<string, unknown> | undefined
      if (action === "resend") {
        const { data: pending, error } = await admin.from("pending_customer_registrations")
          .select("registration_data")
          .eq("email", email)
          .maybeSingle()
        if (error) throw error
        data = pending?.registration_data as Record<string, unknown> | undefined
      }
      const consents = data?.legal_acceptances
      if (!data || !String(data.first_name ?? "").trim() || !String(data.last_name ?? "").trim() || !String(data.phone ?? "").trim() || !String(data.address ?? "").trim() || !Array.isArray(consents) || !["terms_of_service", "privacy_policy"].every((key) => consents.some((entry) => entry?.key === key && entry?.version && entry?.hash))) return fail("Complete all registration details and consent first")
      const existingUser = await findUserByEmail(admin, email)
      if (existingUser?.email_confirmed_at) return fail("This email is already registered. Sign in or reset your password.", 409)
      const { data: existing } = await admin.from("pending_customer_registrations").select("send_count, created_at").eq("email", email).maybeSingle()
      const withinHour = existing && Date.now() - new Date(existing.created_at).getTime() < 3600_000
      if (withinHour && existing.send_count >= MAX_SENDS) return fail("Too many code requests. Try again later.", 429)
      const code = newCode()
      const now = new Date()
      const pending = {
        email, registration_data: data, code_hash: await hash(code),
        expires_at: new Date(now.getTime() + TTL_MINUTES * 60_000).toISOString(),
        created_at: withinHour ? existing.created_at : now.toISOString(),
        sent_at: now.toISOString(), send_count: withinHour ? existing.send_count + 1 : 1, attempts: 0,
      }
      const { error } = await admin.from("pending_customer_registrations").upsert(pending, { onConflict: "email" })
      if (error) throw error
      await sendOtp(email, code, String(data.first_name ?? ""))
      return reply({ ok: true, email })
    }
    if (action === "verify") {
      const code = String(body.code ?? "").trim()
      const password = String(body.password ?? "")
      if (!/^\d{6}$/.test(code)) return fail("Enter the 6-digit code")
      if (password.length < 6 || password.length > 72) return fail("Password does not meet the requirements")
      const { data: pending, error } = await admin.from("pending_customer_registrations").select("*").eq("email", email).maybeSingle()
      if (error) throw error
      if (!pending) return fail("No pending registration found. Start registration again.", 404)
      if (Date.now() > new Date(pending.expires_at).getTime()) {
        await admin.from("pending_customer_registrations").delete().eq("email", email)
        return fail("This code expired. Request a new one.")
      }
      if (pending.attempts >= MAX_ATTEMPTS) return fail("Too many incorrect attempts. Request a new code.", 429)
      if (!constantEqual(await hash(code), pending.code_hash)) {
        const attempts = pending.attempts + 1
        await admin.from("pending_customer_registrations").update({ attempts }).eq("email", email)
        return fail(attempts >= MAX_ATTEMPTS ? "Too many incorrect attempts. Request a new code." : `Incorrect code. ${MAX_ATTEMPTS - attempts} attempts remain.`, attempts >= MAX_ATTEMPTS ? 429 : 400)
      }
      const userMetadata = { ...pending.registration_data, role: "customer" }
      const existingUser = await findUserByEmail(admin, email)
      let userId: string
      if (existingUser) {
        const { error: updateError } = await admin.auth.admin.updateUserById(existingUser.id, {
          password, email_confirm: true, user_metadata: userMetadata,
        })
        if (updateError) throw updateError
        userId = existingUser.id
      } else {
        const { data: created, error: createError } = await admin.auth.admin.createUser({
          email, password, email_confirm: true, user_metadata: userMetadata,
        })
        if (createError) {
          if (createError.message.toLowerCase().includes("already been registered") || createError.message.toLowerCase().includes("already exists")) return fail("This email is already registered. Sign in or reset your password.", 409)
          throw createError
        }
        if (!created.user) throw new Error("Could not create the customer account")
        userId = created.user.id
      }
      await admin.from("pending_customer_registrations").delete().eq("email", email)
      return reply({ ok: true, user_id: userId })
    }
    return fail("Unknown registration action")
  } catch (error) {
    console.error("[customer-registration-otp]", error)
    return fail(error instanceof Error ? error.message : "Registration request failed", 500)
  }
})
