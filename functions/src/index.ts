/**
 * ============================================================================
 * DORMANT / UNUSED CLOUD FUNCTION CODE
 * ============================================================================
 * NOTE: This Cloud Function is currently DORMANT and not deployed or referenced
 * by the client. Firebase Cloud Functions require a billing-enabled Blaze plan.
 * The Ozone calling architecture currently operates in STUN-only P2P mode.
 *
 * This code is preserved here as a dormant reference implementation and can be
 * reactivated in firebase.json if a Blaze plan becomes available in the future.
 * ============================================================================
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as admin from "firebase-admin";

admin.initializeApp();

// Cloudflare Calls TURN Secrets stored in Firebase Secret Manager
const cloudflareAppId = defineSecret("CLOUDFLARE_APP_ID");
const cloudflareTurnKeyId = defineSecret("CLOUDFLARE_TURN_KEY_ID");
const cloudflareApiToken = defineSecret("CLOUDFLARE_API_TOKEN");

interface MintTurnRequest {
  callId: string;
}

interface IceServerConfig {
  urls: string[];
  username?: string;
  credential?: string;
}

interface MintTurnResponse {
  urls: string[];
  username: string;
  credential: string;
  ttl: number;
}

/**
 * HTTPS Callable Cloud Function: mintTurnCredentials
 *
 * Mints short-lived Cloudflare Calls TURN credentials scoped to an active call session.
 * Requires authenticated Firebase user.
 * Secrets CLOUDFLARE_TURN_KEY_ID and CLOUDFLARE_API_TOKEN are injected at runtime
 * and are NEVER logged or exposed to the client.
 */
export const mintTurnCredentials = onCall(
  {
    secrets: [cloudflareAppId, cloudflareTurnKeyId, cloudflareApiToken],
    enforceAppCheck: false, // Optional: enable if App Check configured
  },
  async (request): Promise<MintTurnResponse> => {
    // 1. Verify user authentication
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Authentication is required to mint TURN credentials."
      );
    }

    const { callId } = request.data as MintTurnRequest;
    if (!callId || typeof callId !== "string" || callId.trim().length === 0) {
      throw new HttpsError(
        "invalid-argument",
        "A valid callId must be provided."
      );
    }

    const appId = cloudflareAppId.value() || cloudflareTurnKeyId.value();
    const token = cloudflareApiToken.value();

    if (!appId || !token) {
      throw new HttpsError(
        "failed-precondition",
        "Cloudflare Calls TURN credentials are not configured on the server."
      );
    }

    const ttlSeconds = 3600; // 1-hour short-lived credential per call session

    try {
      const response = await fetch(
        `https://rtc.live.cloudflare.com/v1/turn/keys/${appId}/credentials/generate-ice-servers`,
        {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${token}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ ttl: ttlSeconds }),
        }
      );

      if (!response.ok) {
        const errorText = await response.text();
        // Redact any possible sensitive substrings before logging
        console.error(
          `Cloudflare Calls API returned error ${response.status}: ${errorText.substring(0, 150)}`
        );
        throw new HttpsError(
          "internal",
          `Cloudflare Calls credential generation failed with status ${response.status}`
        );
      }

      const data = await response.json() as { iceServers?: IceServerConfig[] };

      if (!data.iceServers || !Array.isArray(data.iceServers)) {
        throw new HttpsError(
          "internal",
          "Malformed response from Cloudflare Calls API."
        );
      }

      // Locate the TURN server entry containing username and credential
      const turnEntry = data.iceServers.find(
        (s) => s.username && s.credential && s.urls && s.urls.some((u) => u.startsWith("turn:") || u.startsWith("turns:"))
      );

      if (!turnEntry || !turnEntry.username || !turnEntry.credential) {
        throw new HttpsError(
          "internal",
          "No valid TURN relay server returned by Cloudflare Calls."
        );
      }

      // Return sanitized short-lived credentials to client
      return {
        urls: turnEntry.urls,
        username: turnEntry.username,
        credential: turnEntry.credential,
        ttl: ttlSeconds,
      };
    } catch (err: any) {
      if (err instanceof HttpsError) {
        throw err;
      }
      console.error("Unexpected error in mintTurnCredentials:", err.message || err);
      throw new HttpsError("internal", "An error occurred while generating TURN credentials.");
    }
  }
);
