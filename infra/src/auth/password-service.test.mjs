import test from "node:test";
import assert from "node:assert/strict";
import { createPasswordRecord, hashForLoginUpgrade, verifyPassword } from "./password-service.mjs";

test("new passwords use bcrypt cost 12 and verify", async () => {
  const record = await createPasswordRecord("correct horse battery staple");
  assert.match(record.passwordHash, /^\$2b\$12\$/);
  assert.deepEqual(await verifyPassword("correct horse battery staple", record.passwordHash), { valid: true, needsRehash: false });
});

test("legacy plaintext, MD5, and SHA-1 values upgrade after successful login", async () => {
  for (const legacy of ["password", "5f4dcc3b5aa765d61d8327deb882cf99", "5baa61e4c9b93f3f0682250b6cf8331b7ee68fd8"]) {
    const replacement = await hashForLoginUpgrade("password", legacy);
    assert.match(replacement ?? "", /^\$2b\$12\$/);
  }
  assert.equal(await hashForLoginUpgrade("wrong", "legacy-password"), null);
});
