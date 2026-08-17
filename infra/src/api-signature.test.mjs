import test from "node:test";
import assert from "node:assert/strict";
import { generateKeyPairSync, sign } from "node:crypto";
import { canonicalRequest, decodeEnvelope, encodeEnvelope, verifySignedEnvelope } from "./api-signature.mjs";

test("protobuf envelope round trips JSON", () => {
  const encoded = encodeEnvelope({ hello: "gift" }, "req-1", 42);
  const decoded = decodeEnvelope(encoded);
  assert.deepEqual(JSON.parse(decoded.json), { hello: "gift" });
  assert.equal(decoded.requestId, "req-1");
  assert.equal(decoded.serverTimeMs, 42);
});

test("signed envelope verifies once and rejects replay", async () => {
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const jwk = publicKey.export({ format: "jwk" });
  const x963 = Buffer.concat([Buffer.from([4]), Buffer.from(jwk.x, "base64url"), Buffer.from(jwk.y, "base64url")]).toString("base64");
  const body = encodeEnvelope({ surface: "home" });
  const timestamp = Date.now(), nonce = "nonce-12345678901";
  const signature = sign("sha256", Buffer.from(canonicalRequest("POST", "/v2/recommendations", timestamp, nonce, body)), privateKey).toString("base64");
  let nonceWritten = false;
  const ddb = { send: async (command) => {
    if (command.input.Key) return { Item: { publicKey: x963 } };
    if (nonceWritten) throw new Error("duplicate");
    nonceWritten = true; return {};
  } };
  const event = { body: body.toString("base64"), isBase64Encoded: true, headers: {
    "content-type": "application/x-protobuf", "x-api-key-id": "device",
    "x-api-timestamp": String(timestamp), "x-api-nonce": nonce, "x-api-signature": signature,
  } };
  assert.equal((await verifySignedEnvelope({ ddb, table: "config", event, method: "POST", path: "/v2/recommendations", now: timestamp })).ok, true);
  assert.equal((await verifySignedEnvelope({ ddb, table: "config", event, method: "POST", path: "/v2/recommendations", now: timestamp })).reason, "apisignature");
});

test("unsigned protobuf request fails with apisignature", async () => {
  const result = await verifySignedEnvelope({
    ddb: { send: async () => { throw new Error("must not read storage"); } },
    table: "config",
    event: { headers: { "content-type": "application/x-protobuf" }, body: "" },
    method: "POST", path: "/v2/recommendations",
  });
  assert.deepEqual(result, { ok: false, reason: "apisignature" });
});
