import bcrypt from "bcryptjs";
import { createHash, timingSafeEqual } from "node:crypto";

export const BCRYPT_ROUNDS = 12;

const digest = (algorithm, value) => createHash(algorithm).update(value, "utf8").digest("hex");

function constantTimeStringEqual(left, right) {
  const a = Buffer.from(left, "utf8");
  const b = Buffer.from(right, "utf8");
  return a.length === b.length && timingSafeEqual(a, b);
}

function legacyMatch(password, stored) {
  if (constantTimeStringEqual(password, stored)) return true;
  if (/^[a-f0-9]{32}$/i.test(stored) && constantTimeStringEqual(digest("md5", password), stored.toLowerCase())) return true;
  if (/^[a-f0-9]{40}$/i.test(stored) && constantTimeStringEqual(digest("sha1", password), stored.toLowerCase())) return true;
  return false;
}

export function isCurrentHash(value) {
  return typeof value === "string" && /^\$2[aby]\$12\$/.test(value);
}

export async function hashPassword(password) {
  if (typeof password !== "string" || password.length < 8) {
    throw new Error("Password must be at least 8 characters");
  }
  return bcrypt.hash(password, BCRYPT_ROUNDS);
}

// Returns the upgrade hash when a legacy password succeeds. Callers must persist
// it atomically with the login, and must never log either input or output.
export async function verifyPassword(password, storedHash) {
  if (typeof password !== "string" || typeof storedHash !== "string") return { valid: false };
  if (storedHash.startsWith("$2")) {
    return { valid: await bcrypt.compare(password, storedHash), needsRehash: !isCurrentHash(storedHash) };
  }
  const valid = legacyMatch(password, storedHash);
  return { valid, needsRehash: valid };
}

export async function hashForLoginUpgrade(password, storedHash) {
  const result = await verifyPassword(password, storedHash);
  return result.valid && result.needsRehash ? hashPassword(password) : null;
}

export async function createPasswordRecord(password) {
  return { passwordHash: await hashPassword(password), passwordHashVersion: 1 };
}

export async function changePassword(currentPassword, newPassword, storedHash) {
  const current = await verifyPassword(currentPassword, storedHash);
  if (!current.valid) throw new Error("Invalid credentials");
  return createPasswordRecord(newPassword);
}
