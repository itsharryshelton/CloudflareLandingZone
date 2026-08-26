/**
 * Security Headers and Edge Telemetry Worker.
 * NOTE: This .js file is purely for example, I generated it using Gemini to provide an obvious example about how this would interface with the terraform.
 *
 * Intercepts origin responses to enforce HTTP security headers and asynchronously
 * dispatches request telemetry without blocking the client response lifecycle.
 *
 * Bindings (configured via accounts/<account>/workers.tfvars):
 *   CONFIG       kv_namespace         optional. Dynamic security header overrides.
 *   API_SECRET   secrets_store_secret optional. Authentication token for telemetry endpoint.
 */

const DEFAULT_SECURITY_HEADERS = {
  "Strict-Transport-Security": "max-age=31536000; includeSubDomains; preload",
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
  "Referrer-Policy": "strict-origin-when-cross-origin",
  "Permissions-Policy": "accelerometer=(), camera=(), geolocation=(), microphone=(), payment=()",
  "Content-Security-Policy": "default-src 'self'; img-src 'self' data: https:; script-src 'self'; style-src 'self' 'unsafe-inline';",
};

/**
 * Asynchronously dispatches request telemetry to a monitoring endpoint.
 * Executed via ctx.waitUntil() to avoid adding latency to the client response.
 *
 * @param {Request} request
 * @param {Response} response
 * @param {number} durationMs
 * @param {string | undefined} apiSecret
 */
const recordTelemetry = async (request, response, durationMs, apiSecret) => {
  if (!apiSecret) {
    return;
  }

  const payload = {
    timestamp: new Date().toISOString(),
    method: request.method,
    url: request.url,
    status: response.status,
    durationMs,
    cfRay: request.headers.get("cf-ray"),
    country: request.cf ? request.cf.country : null,
  };

  try {
    // In production, dispatch to your logging or SIEM pipeline
    // Example: fetch("https://telemetry.internal/events", { method: "POST", headers: { "Authorization": `Bearer ${apiSecret}` }, body: JSON.stringify(payload) })
    void payload;
  } catch (error) {
    console.error("Failed to dispatch telemetry:", error);
  }
};

export default {
  async fetch(request, env, ctx) {
    const startTime = Date.now();

    try {
      // Forward request to origin
      const response = await fetch(request);

      // Clone headers to mutate response
      const newHeaders = new Headers(response.headers);

      // Apply default security headers if not already set by the origin
      for (const [headerName, headerValue] of Object.entries(DEFAULT_SECURITY_HEADERS)) {
        if (!newHeaders.has(headerName)) {
          newHeaders.set(headerName, headerValue);
        }
      }

      // Check KV for runtime configuration overrides if available
      if (env.CONFIG) {
        const customCsp = await env.CONFIG.get("csp_override");
        if (customCsp) {
          newHeaders.set("Content-Security-Policy", customCsp);
        }
      }

      const modifiedResponse = new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers: newHeaders,
      });

      // Asynchronously log telemetry without blocking response delivery
      if (ctx && typeof ctx.waitUntil === "function") {
        const durationMs = Date.now() - startTime;
        ctx.waitUntil(recordTelemetry(request, modifiedResponse, durationMs, env.API_SECRET));
      }

      return modifiedResponse;
    } catch (error) {
      console.error("Security headers worker encountered an error:", error);
      return fetch(request);
    }
  },
};
