// supabase/functions/send-notification/index.ts
// Uses FCM HTTP v1 API (modern, not legacy)
// Required secret: FIREBASE_SERVICE_ACCOUNT_JSON

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { create, getNumericDate } from "https://deno.land/x/djwt@v2.8/mod.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SERVICE_ACCOUNT_JSON = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON")!;

// Generate a short-lived OAuth2 access token from the service account
async function getAccessToken(): Promise<string> {
  const serviceAccount = JSON.parse(SERVICE_ACCOUNT_JSON);

  const now = getNumericDate(0);
  const exp = getNumericDate(60 * 60); // 1 hour

  // Import the private key
  const privateKey = serviceAccount.private_key as string;
  const pemContents = privateKey
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\n/g, "");

  const binaryDer = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryDer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  // Build JWT claim for Google OAuth2
  const jwt = await create(
    { alg: "RS256", typ: "JWT" },
    {
      iss: serviceAccount.client_email,
      sub: serviceAccount.client_email,
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: exp,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
    },
    cryptoKey
  );

  // Exchange JWT for access token
  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  const tokenData = await tokenRes.json();
  return tokenData.access_token;
}

serve(async (req) => {
  try {
    const { type, actorId, targetUserId, postId } = await req.json();

    // Never notify yourself
    if (actorId === targetUserId) {
      return new Response(JSON.stringify({ skipped: true }), { status: 200 });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    // Get actor's username
    const { data: actor } = await supabase
      .from("profiles")
      .select("username")
      .eq("id", actorId)
      .single();

    // Get target user's FCM token
    const { data: tokenRow } = await supabase
      .from("fcm_tokens")
      .select("token")
      .eq("user_id", targetUserId)
      .maybeSingle();

    if (!tokenRow?.token) {
      return new Response(JSON.stringify({ skipped: "no_token" }), {
        status: 200,
      });
    }

    // Build notification body
    let body = "";
    switch (type) {
      case "like":
        body = `${actor?.username} liked your post ❤️`;
        break;
      case "comment":
        body = `${actor?.username} commented on your post 💬`;
        break;
      case "follow":
        body = `${actor?.username} started following you 🔔`;
        break;
      case "message":
        body = `${actor?.username} sent you a message 💌`;
        break;
      default:
        body = "You have a new notification";
    }

    // Get OAuth2 access token
    const accessToken = await getAccessToken();
    const serviceAccount = JSON.parse(SERVICE_ACCOUNT_JSON);
    const projectId = serviceAccount.project_id;

    // Send via FCM HTTP v1
    const fcmRes = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${accessToken}`,
        },
        body: JSON.stringify({
          message: {
            token: tokenRow.token,
            notification: {
              title: "PigiGo 🐦",
              body,
            },
            android: {
              priority: "high",
              notification: {
                channel_id: "pigigo_high_importance",
                click_action: "FLUTTER_NOTIFICATION_CLICK",
                sound: "default",
              },
            },
            data: {
              type,
              postId: postId ?? "",
              actorId,
            },
          },
        }),
      }
    );

    const fcmResult = await fcmRes.json();

    return new Response(JSON.stringify({ success: true, fcmResult }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
    });
  }
});