import { createHash, createPublicKey, randomUUID, verify as verifySignature } from "node:crypto";
import { GetCommand, PutCommand } from "@aws-sdk/lib-dynamodb";

export const PROTO_CONTENT_TYPE = "application/x-protobuf";

function varint(value) {
  const bytes = [];
  let n = BigInt(value);
  do {
    let byte = Number(n & 0x7fn);
    n >>= 7n;
    if (n) byte |= 0x80;
    bytes.push(byte);
  } while (n);
  return Buffer.from(bytes);
}

function readVarint(bytes, cursor) {
  let value = 0n, shift = 0n, index = cursor;
  while (index < bytes.length) {
    const byte = bytes[index++];
    value |= BigInt(byte & 0x7f) << shift;
    if (!(byte & 0x80)) return { value: Number(value), cursor: index };
    shift += 7n;
    if (shift > 63n) throw new Error("invalid protobuf varint");
  }
  throw new Error("truncated protobuf varint");
}

function field(tag, bytes) {
  return Buffer.concat([Buffer.from([tag]), varint(bytes.length), bytes]);
}

// ApiEnvelope { bytes json = 1; string request_id = 2; int64 server_time_ms = 3; }
export function encodeEnvelope(payload, requestId = randomUUID(), serverTimeMs = Date.now()) {
  const json = Buffer.isBuffer(payload) ? payload : Buffer.from(JSON.stringify(payload));
  return Buffer.concat([
    field(0x0a, json),
    field(0x12, Buffer.from(requestId)),
    Buffer.from([0x18]), varint(serverTimeMs),
  ]);
}

export function decodeEnvelope(input) {
  const bytes = Buffer.from(input);
  let cursor = 0, json = Buffer.alloc(0), requestId = "", serverTimeMs = 0;
  while (cursor < bytes.length) {
    const key = readVarint(bytes, cursor); cursor = key.cursor;
    const number = key.value >> 3, wire = key.value & 7;
    if (wire === 2) {
      const length = readVarint(bytes, cursor); cursor = length.cursor;
      const value = bytes.subarray(cursor, cursor + length.value); cursor += length.value;
      if (number === 1) json = value;
      if (number === 2) requestId = value.toString("utf8");
    } else if (wire === 0) {
      const value = readVarint(bytes, cursor); cursor = value.cursor;
      if (number === 3) serverTimeMs = value.value;
    } else {
      throw new Error("unsupported protobuf wire type");
    }
  }
  return { json, requestId, serverTimeMs };
}

export function canonicalRequest(method, path, timestamp, nonce, body) {
  const digest = createHash("sha256").update(body).digest("hex");
  return `${method.toUpperCase()}\n${path}\n${timestamp}\n${nonce}\n${digest}`;
}

function header(event, name) {
  const headers = event.headers || {};
  return headers[name] || headers[name.toLowerCase()] || headers[name.toUpperCase()] || "";
}

function publicKeyFromX963(value) {
  const bytes = Buffer.from(value, "base64");
  if (bytes.length !== 65 || bytes[0] !== 4) throw new Error("invalid P-256 public key");
  return createPublicKey({ key: {
    kty: "EC", crv: "P-256",
    x: bytes.subarray(1, 33).toString("base64url"),
    y: bytes.subarray(33, 65).toString("base64url"),
  }, format: "jwk" });
}

export async function registerDeviceKey({ ddb, table, auth, body }) {
  if (!auth?.ok || auth.via === "admin") return { statusCode: 401, body: { error: "authentication required" } };
  const keyId = String(body.keyId || "").slice(0, 96);
  const publicKey = String(body.publicKey || "").slice(0, 256);
  if (!keyId || !publicKey) return { statusCode: 400, body: { error: "keyId and publicKey required" } };
  try { publicKeyFromX963(publicKey); } catch { return { statusCode: 400, body: { error: "invalid public key" } }; }
  await ddb.send(new PutCommand({
    TableName: table,
    Item: { key: `api-key#${keyId}`, keyId, publicKey, ownerId: auth.sub, createdAt: Date.now() },
    ConditionExpression: "attribute_not_exists(#key) OR ownerId = :owner",
    ExpressionAttributeNames: { "#key": "key" },
    ExpressionAttributeValues: { ":owner": auth.sub },
  }));
  return { statusCode: 201, body: { ok: true, keyId } };
}

export async function verifySignedEnvelope({ ddb, table, event, method, path, now = Date.now() }) {
  if (header(event, "x-admin-token")) return { ok: true, admin: true };
  const keyId = header(event, "x-api-key-id");
  const timestamp = Number(header(event, "x-api-timestamp"));
  const nonce = header(event, "x-api-nonce");
  const signature = header(event, "x-api-signature");
  const contentType = header(event, "content-type").split(";")[0].trim().toLowerCase();
  if (!keyId || !timestamp || !nonce || !signature || contentType !== PROTO_CONTENT_TYPE) {
    return { ok: false, reason: "apisignature" };
  }
  if (Math.abs(now - timestamp) > 5 * 60_000 || nonce.length < 16 || nonce.length > 128) {
    return { ok: false, reason: "apisignature" };
  }
  const raw = Buffer.from(event.body || "", event.isBase64Encoded ? "base64" : "binary");
  const found = await ddb.send(new GetCommand({ TableName: table, Key: { key: `api-key#${keyId}` } }));
  if (!found.Item?.publicKey) return { ok: false, reason: "apisignature" };
  let valid = false;
  try {
    valid = verifySignature("sha256", Buffer.from(canonicalRequest(method, path, timestamp, nonce, raw)), publicKeyFromX963(found.Item.publicKey), Buffer.from(signature, "base64"));
  } catch {}
  if (!valid) return { ok: false, reason: "apisignature" };
  try {
    await ddb.send(new PutCommand({
      TableName: table,
      Item: { key: `api-nonce#${keyId}#${nonce}`, createdAt: now, expiresAt: Math.floor(now / 1000) + 600 },
      ConditionExpression: "attribute_not_exists(#key)",
      ExpressionAttributeNames: { "#key": "key" },
    }));
  } catch { return { ok: false, reason: "apisignature" }; }
  try {
    const envelope = decodeEnvelope(raw);
    return {
      ok: true,
      body: envelope.json.length ? JSON.parse(envelope.json.toString("utf8")) : {},
      requestId: envelope.requestId,
      ownerId: found.Item.ownerId,
    };
  } catch { return { ok: false, reason: "invalid protobuf" }; }
}

export function protobufResponse(statusCode, payload, headers = {}) {
  const bytes = encodeEnvelope(payload);
  return {
    statusCode,
    headers: { ...headers, "content-type": PROTO_CONTENT_TYPE },
    body: bytes.toString("base64"),
    isBase64Encoded: true,
  };
}
