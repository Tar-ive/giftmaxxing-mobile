// HTTP adapter — runs the EXISTING Lambda handler (handler.mjs) as a long-lived
// Node server on AWS App Runner (or any container host), sidestepping the Lambda
// per-account concurrency cap. One Node process multiplexes many concurrent
// I/O-bound requests on the event loop.
//
// It translates each incoming Node request into the API Gateway HTTP API (v2)
// event shape that handler.mjs already expects, invokes the handler, and writes
// the { statusCode, headers, body } back. Two things API Gateway used to do that
// we must now do here:
//   1. CORS — add access-control-* headers to every response (the browser calls
//      this cross-origin from Vercel with a Bearer token, no cookies, so "*" is
//      safe).
//   2. Health — answer /healthz (and /) directly for App Runner health checks,
//      bypassing the handler + auth gate.
import http from "node:http";
import { handler } from "./handler.mjs";

const PORT = Number(process.env.PORT || 8080);

// "*" is safe because the API authenticates with Authorization: Bearer /
// x-admin-token (never cookies), so credentials mode is never used. Set
// CORS_ALLOW_ORIGIN to lock it down to the Vercel origin if desired.
const CORS_ALLOW_ORIGIN = process.env.CORS_ALLOW_ORIGIN || "*";
const MAX_BODY_BYTES = 6 * 1024 * 1024; // visual-search posts base64 images

function corsHeaders(origin) {
  return {
    "access-control-allow-origin": CORS_ALLOW_ORIGIN === "*" ? origin || "*" : CORS_ALLOW_ORIGIN,
    "access-control-allow-methods": "GET,POST,PUT,DELETE,OPTIONS",
    "access-control-allow-headers": "content-type,authorization,x-admin-token,x-api-key-id,x-api-timestamp,x-api-nonce,x-api-signature",
    "access-control-max-age": "3600",
    vary: "origin",
  };
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on("data", (c) => {
      size += c.length;
      if (size > MAX_BODY_BYTES) {
        reject(new Error("payload too large"));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on("end", () => resolve(chunks.length ? Buffer.concat(chunks) : undefined));
    req.on("error", reject);
  });
}

const server = http.createServer(async (req, res) => {
  const origin = req.headers.origin;
  try {
    const url = new URL(req.url, "http://localhost");
    const path = url.pathname;
    const method = req.method || "GET";

    // App Runner health check — never touch the handler/auth/DynamoDB.
    if (path === "/healthz" || path === "/") {
      res.writeHead(200, { "content-type": "application/json", ...corsHeaders(origin) });
      res.end(JSON.stringify({ ok: true, service: "giftmaxxing-api" }));
      return;
    }

    // API Gateway HTTP API joins multi-valued query params with commas; mirror
    // that so handler's parseList(qs.vibes) etc. behave identically.
    const qs = {};
    for (const [k, v] of url.searchParams) qs[k] = k in qs ? `${qs[k]},${v}` : v;

    const bodyBytes = method === "GET" || method === "HEAD" ? undefined : await readBody(req);

    // Real client IP is in X-Forwarded-For behind App Runner's load balancer;
    // fall back to the socket address. Used only as a last-resort rate-limit key.
    const xff = req.headers["x-forwarded-for"];
    const sourceIp = (Array.isArray(xff) ? xff[0] : xff)?.split(",")[0]?.trim() || req.socket?.remoteAddress;

    const event = {
      version: "2.0",
      rawPath: path,
      requestContext: { http: { method, path, sourceIp } },
      queryStringParameters: Object.keys(qs).length ? qs : null,
      headers: req.headers, // Node lowercases header names — matches API Gateway
      body: bodyBytes?.toString("base64"),
      isBase64Encoded: Boolean(bodyBytes),
    };

    const result = await handler(event);
    // Our CORS headers win over anything the handler set (it set none for origin).
    const headers = { ...(result?.headers || {}), ...corsHeaders(origin) };
    res.writeHead(result?.statusCode || 200, headers);
    res.end(result?.isBase64Encoded
      ? Buffer.from(result?.body ?? "", "base64")
      : result?.body ?? "");
  } catch (err) {
    console.error("server adapter error", err);
    res.writeHead(500, { "content-type": "application/json", ...corsHeaders(origin) });
    res.end(JSON.stringify({ error: "internal error" }));
  }
});

// Generous keep-alive so the load balancer reuses connections.
server.keepAliveTimeout = 65000;
server.headersTimeout = 66000;
server.requestTimeout = 30000;

server.listen(PORT, "0.0.0.0", () => {
  console.log(`giftmaxxing-api (App Runner adapter) listening on :${PORT}`);
});
