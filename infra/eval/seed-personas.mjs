#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { PERSONAS } from "./personas.mjs";

const read = (name) => process.argv[process.argv.indexOf(name) + 1];
const viewer = read("--viewer-user-id");
if (!viewer) throw new Error("--viewer-user-id USER_ID is required");
const table = process.env.TASTE_PROFILES_TABLE || "giftmaxxing-dev-taste-profiles";
const region = process.env.AWS_REGION || "us-east-1";
const dir = mkdtempSync(join(tmpdir(), "giftmaxxing-personas-"));
for (let i = 0; i < PERSONAS.length; i += 25) {
  const requests = PERSONAS.slice(i, i + 25).map((p) => ({ PutRequest: { Item: {
    profileId: { S: p.profileId }, ownerId: { S: viewer }, profileType: { S: "synthetic" }, status: { S: "active" },
    authorizedViewerIds: { L: [{ S: viewer }] }, version: { N: "1" }, preferredPrice: { N: String(p.budget) },
    labelWeights: { M: Object.fromEntries([...p.positiveLabels.map((x) => [x, { N: "2" }]), ...p.negativeLabels.map((x) => [x, { N: "-2" }])]) },
    kindWeights: { M: Object.fromEntries(p.kindPreferences.map((x, index) => [x, { N: String(2 - index * 0.4) }])) },
    uncertainty: { M: Object.fromEntries([...p.positiveLabels, ...p.negativeLabels].map((x) => [x, { N: "0.5" }])) },
    positiveItemIds: { L: p.seedLikes.map((x) => ({ S: x })) }, negativeItemIds: { L: p.seedDislikes.map((x) => ({ S: x })) },
    updatedAt: { N: String(Date.now()) },
  } } }));
  const path = join(dir, `batch-${i}.json`);
  writeFileSync(path, JSON.stringify({ [table]: requests }));
  execFileSync("aws", ["dynamodb", "batch-write-item", "--request-items", `file://${path}`, "--region", region], { stdio: "inherit" });
}
console.log(`seeded ${PERSONAS.length} profiles into ${table}`);
