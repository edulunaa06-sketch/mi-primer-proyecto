// Backend mínimo para el intercambio OAuth de Strava (Cloudflare Workers).
// Guarda el client_secret como secreto del Worker, NUNCA en la app iOS.
//
// Variables (wrangler secret put …):
//   STRAVA_CLIENT_ID      → tu Client ID (número)
//   STRAVA_CLIENT_SECRET  → tu Client Secret
//
// Endpoints que usa la app:
//   POST /strava/token    { "code": "…" }           → intercambia el código por tokens
//   POST /strava/refresh  { "refresh_token": "…" }  → renueva el access token
// Devuelve el JSON de Strava tal cual (access_token, refresh_token, expires_at, scope…).

export default {
  async fetch(request, env) {
    if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
    const url = new URL(request.url);
    let body;
    try { body = await request.json(); } catch { return json({ error: "invalid_json" }, 400); }

    const params = new URLSearchParams({
      client_id: env.STRAVA_CLIENT_ID,
      client_secret: env.STRAVA_CLIENT_SECRET,
    });

    if (url.pathname === "/strava/token" && typeof body.code === "string") {
      params.set("grant_type", "authorization_code");
      params.set("code", body.code);
    } else if (url.pathname === "/strava/refresh" && typeof body.refresh_token === "string") {
      params.set("grant_type", "refresh_token");
      params.set("refresh_token", body.refresh_token);
    } else {
      return json({ error: "not_found" }, 404);
    }

    const res = await fetch("https://www.strava.com/oauth/token", { method: "POST", body: params });
    const data = await res.json();
    // No se devuelve información del atleta: la app solo necesita los tokens.
    const { access_token, refresh_token, expires_at, expires_in, scope, token_type } = data;
    if (!res.ok || !access_token) return json({ error: "strava_error", status: res.status }, 502);
    return json({ access_token, refresh_token, expires_at, expires_in, scope, token_type }, 200);
  },
};

function json(obj, status) {
  return new Response(JSON.stringify(obj), { status, headers: { "content-type": "application/json" } });
}
