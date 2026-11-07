// Supabase Edge Function: send-push-notification
//
// Sends FCM push notifications to app users via the Firebase Cloud
// Messaging HTTP v1 API.
//
// Body:
//   {
//     "title":     "Order Update",           // required
//     "body":      "Your laundry is ready!", // required
//     "audience":  "all" | "customer" | "staff" | "rider",  // default "all"
//     "user_ids":  ["<auth-user-id>", ...],  // optional explicit targets
//     "data":      { "type": "order_update", "order_id": "..." } // optional payload
//   }
//
// Security:
//   - Requires a valid Supabase JWT (default verify_jwt = true). An
//     authenticated caller can only send to a limited number of users
//     (rate-limited); trusted callers should use the service role key.
//   - The Firebase service account lives in function secrets, never in
//     the app binary.
//
// Deploy:
//   supabase functions deploy send-push-notification
//   supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON='<contents of the JSON key file>'
//
// Create the service account in Firebase Console -> Project settings ->
// Service accounts -> Generate new private key, with the role
// "Firebase Cloud Messaging API Admin".

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const FCM_SCOPE =
  "https://www.googleapis.com/auth/firebase.messaging";
const FCM_ENDPOINT = "https://fcm.googleapis.com/v1/projects/{projectId}/messages:send";

// Batch size for FCM fan-out; HTTP v1 has no batch endpoint anymore.
const MAX_TOKENS_PER_REQUEST = 500;
// Cap for user-directed sends from ordinary authenticated callers.
const MAX_USER_IDS_FOR_AUTHED = 100;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function fail(error: string, status = 400): Response {
  return json({ error }, status);
}

function createAdminClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  }
  return createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

// ---------- Firebase service-account auth (JWT -> OAuth2 access token) -----

function base64UrlEncode(input: string | Uint8Array): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
}

let cachedAccessToken: { token: string; expiresAt: number } | null = null;

async function getAccessToken(account: ServiceAccount): Promise<string> {
  if (cachedAccessToken && Date.now() < cachedAccessToken.expiresAt - 60_000) {
    return cachedAccessToken.token;
  }

  const header = base64UrlEncode(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const now = Math.floor(Date.now() / 1000);
  const claims = base64UrlEncode(
    JSON.stringify({
      iss: account.client_email,
      scope: FCM_SCOPE,
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    }),
  );
  const unsignedJwt = `${header}.${claims}`;

  const privateKeyPem = account.private_key.replace(/\\n/g, "\n");
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(privateKeyPem),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsignedJwt),
  );
  const signedPart = base64UrlEncode(new Uint8Array(signature));
  const jwt = `${unsignedJwt}.${signedPart}`;

  const resp = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!resp.ok) {
    throw new Error(`Google token endpoint error ${resp.status}: ${await resp.text()}`);
  }
  const data = await resp.json();
  cachedAccessToken = {
    token: data.access_token,
    expiresAt: Date.now() + (data.expires_in ?? 3600) * 1000,
  };
  return cachedAccessToken.token;
}

function pemToDer(pem: string): Uint8Array {
  const body = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

async function getServiceAccount(): Promise<ServiceAccount> {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!raw) {
    throw new Error("FIREBASE_SERVICE_ACCOUNT_JSON secret is not set");
  }
  const parsed = JSON.parse(raw);
  return {
    client_email: parsed.client_email,
    private_key: parsed.private_key,
    project_id: parsed.project_id,
  };
}

// ---------------------------------------------------------------------------

async function sendToFcm(
  account: ServiceAccount,
  accessToken: string,
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<{ ok: boolean; invalid: boolean; detail?: string }> {
  const url = FCM_ENDPOINT.replace("{projectId}", account.project_id);
  const resp = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      message: {
        token,
        notification: { title, body },
        data,
        android: {
          priority: "high",
          notification: {
            channel_id: "infinitywash_default",
            sound: "default",
          },
        },
        apns: { headers: { "apns-priority": "10" } },
      },
    }),
  });

  if (resp.ok) return { ok: true, invalid: false };

  const detail = await resp.text();
  // Token no longer valid: report so the caller can prune it.
  const invalid =
    resp.status === 404 ||
    resp.status === 410 ||
    detail.includes("UNREGISTERED") ||
    detail.includes("INVALID_ARGUMENT");
  return { ok: false, invalid, detail };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return fail("Method not allowed", 405);
  }

  let body: {
    title?: string;
    body?: string;
    audience?: string;
    user_ids?: string[];
    data?: Record<string, unknown>;
  };
  try {
    body = await req.json();
  } catch {
    return fail("Invalid JSON body");
  }

  const title = (body.title ?? "").trim();
  const messageBody = (body.body ?? "").trim();
  if (!title || !messageBody) {
    return fail("Both title and body are required");
  }

  // Only string values are allowed in FCM data payloads.
  const data: Record<string, string> = {};
  for (const [k, v] of Object.entries(body.data ?? {})) {
    if (v !== null && v !== undefined) data[k] = String(v);
  }

  const audience = (body.audience ?? "all").toLowerCase();
  if (!["all", "customer", "staff", "rider"].includes(audience)) {
    return fail("audience must be one of: all, customer, staff, rider");
  }

  const userIds = body.user_ids ?? [];
  const isServiceRole =
    (req.headers.get("authorization") ?? "").includes(
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "\u0000",
    );

  // Rate-limit ordinary authenticated callers pushing to explicit users.
  if (!isServiceRole && userIds.length > MAX_USER_IDS_FOR_AUTHED) {
    return fail(
      `Authenticated callers may target at most ${MAX_USER_IDS_FOR_AUTHED} users`,
      429,
    );
  }

  let admin;
  try {
    admin = createAdminClient();
  } catch (err) {
    console.error("[send-push] admin client error:", err);
    return fail("Server configuration error", 500);
  }

  let account: ServiceAccount;
  let accessToken: string;
  try {
    account = await getServiceAccount();
    accessToken = await getAccessToken(account);
  } catch (err) {
    console.error("[send-push] firebase auth error:", err);
    return fail("Push service not configured", 500);
  }

  try {
    // Resolve target tokens.
    let query = admin
      .from("fcm_tokens")
      .select("user_id, token");

    if (userIds.length > 0) {
      query = query.in("user_id", userIds);
    } else if (audience !== "all") {
      // Filter by role through the profiles table.
      const { data: profiles, error: profileError } = await admin
        .from("profiles")
        .select("supabase_user_id")
        .eq("role", audience)
        .eq("status", "active");
      if (profileError) throw profileError;

      const ids = (profiles ?? []).map((p: { supabase_user_id: string }) => p.supabase_user_id);
      if (ids.length === 0) {
        return json({ ok: true, sent: 0, invalid_tokens: 0, detail: "No users in audience" });
      }
      // in() is capped at 100k values; app scale is far below that.
      query = query.in("user_id", ids);
    }

    const { data: tokenRows, error: tokenError } = await query;
    if (tokenError) throw tokenError;

    const rows: { user_id: string; token: string }[] = tokenRows ?? [];
    if (rows.length === 0) {
      return json({ ok: true, sent: 0, invalid_tokens: 0, detail: "No registered devices" });
    }

    // Fan out in batches, tracking dead tokens for pruning.
    let sent = 0;
    const invalidTokens: string[] = [];
    const errors: { token: string; detail: string }[] = [];

    for (let i = 0; i < rows.length; i += MAX_TOKENS_PER_REQUEST) {
      const batch = rows.slice(i, i + MAX_TOKENS_PER_REQUEST);
      const results = await Promise.all(
        batch.map((row) =>
          sendToFcm(account, accessToken, row.token, title, messageBody, data),
        ),
      );
      for (let j = 0; j < batch.length; j++) {
        const r = results[j];
        if (r.ok) sent++;
        else if (r.invalid) invalidTokens.push(batch[j].token);
        else errors.push({ token: batch[j].token, detail: r.detail ?? "unknown" });
      }
    }

    // Prune tokens FCM says are no longer registered.
    if (invalidTokens.length > 0) {
      await admin.from("fcm_tokens").delete().in("token", invalidTokens);
    }

    return json({
      ok: true,
      audience,
      targeted_devices: rows.length,
      sent,
      invalid_tokens_removed: invalidTokens.length,
      errors: errors.slice(0, 10),
    });
  } catch (err) {
    console.error("[send-push] unhandled error:", err);
    return fail("Internal server error", 500);
  }
});
