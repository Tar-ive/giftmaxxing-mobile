#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const args = process.argv.slice(2);
const rollback = args.includes("--rollback");
const version = args[args.indexOf("--version") + 1];
const region = process.env.AWS_REGION || "us-east-1";
const bucket = process.env.RECOMMENDER_ML_BUCKET;
const group = process.env.RECOMMENDER_MODEL_PACKAGE_GROUP || "giftmaxxing-dev-recommender";
const activeKey = process.env.RECOMMENDER_ACTIVE_KEY || "models/active.json";
if (!bucket) throw new Error("RECOMMENDER_ML_BUCKET is required");
const run = (...argv) => execFileSync("aws", [...argv, "--region", region], { encoding: "utf8" });
const dir = mkdtempSync(join(tmpdir(), "giftmaxxing-promote-"));
const activePath = join(dir, "active.json");
try { run("s3", "cp", `s3://${bucket}/${activeKey}`, activePath); } catch { writeFileSync(activePath, "{}"); }
const active = JSON.parse(readFileSync(activePath, "utf8"));

if (rollback) {
  if (!active.previous) throw new Error("no previous approved model is recorded");
  const next = { ...active.previous, previous: { ...active, previous: undefined }, rollbackAt: new Date().toISOString() };
  writeFileSync(activePath, JSON.stringify(next, null, 2));
  run("s3", "cp", activePath, `s3://${bucket}/${activeKey}`);
  console.log(JSON.stringify(next, null, 2));
  process.exit(0);
}
if (!version || !/^\d+$/.test(version)) throw new Error("use --version MODEL_VERSION");
const gatePath = join(dir, "gate.json");
run("s3", "cp", `s3://${bucket}/evaluations/${version}-gate.json`, gatePath);
const gate = JSON.parse(readFileSync(gatePath, "utf8"));
if (!gate.passed) throw new Error("candidate has not passed every promotion gate");
if (!gate.artifact?.startsWith("s3://")) throw new Error("candidate artifact is missing");
const artifactPath = join(dir, "model.tar.gz");
run("s3", "cp", gate.artifact, artifactPath);
execFileSync("tar", ["-xzf", artifactPath, "-C", dir, "swipe_lr.json"]);
const model = JSON.parse(readFileSync(join(dir, "swipe_lr.json"), "utf8"));
run("sagemaker", "update-model-package", "--model-package-arn", gate.candidate, "--model-approval-status", "Approved");
const next = {
  version, modelPackageArn: gate.candidate, runId: gate.runId,
  model,
  approvedAt: new Date().toISOString(), approvedBy: process.env.USER || "operator",
  previous: active.version ? { version: active.version, modelPackageArn: active.modelPackageArn, runId: active.runId, approvedAt: active.approvedAt } : null,
};
writeFileSync(activePath, JSON.stringify(next, null, 2));
run("s3", "cp", activePath, `s3://${bucket}/${activeKey}`);
console.log(JSON.stringify(next, null, 2));
