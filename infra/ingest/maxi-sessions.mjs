// Pull Maxi conversation turns out of CloudWatch into a real .jsonl file.
//
// Why this exists: the API logs token counts and cost, which cannot answer the
// question you actually have when something goes wrong — "Maxi said it added
// that to my cart, so did it call add_to_cart or did it just say so?". Every
// turn now emits one structured `maxi session {...}` line; this collects them.
//
// One JSON object per line, oldest first:
//   { at, userId, model, tier, user, say, tools[], actions[], pins, shown,
//     brief, reconciled, usedIn, usedOut, costUsd }
//
// Usage:
//   export AWS_PROFILE=dev_sso_giftmaxxing
//   node maxi-sessions.mjs                       # last 2h -> maxi-sessions.jsonl
//   node maxi-sessions.mjs --since 24h --user google_123
//   node maxi-sessions.mjs --since 1h --print    # human-readable to stdout
//   node maxi-sessions.mjs --out /tmp/today.jsonl
//
// Read it back with jq, e.g. every turn that CLAIMED a cart add:
//   jq -c 'select(.say|test("cart";"i"))|{at,say,actions,reconciled}' maxi-sessions.jsonl
import { writeFile } from "node:fs/promises";
import {
  CloudWatchLogsClient,
  DescribeLogGroupsCommand,
  FilterLogEventsCommand,
} from "@aws-sdk/client-cloudwatch-logs";

const REGION = process.env.AWS_REGION || "us-east-1";
const ENV_PREFIX = process.env.ENV_PREFIX || "giftmaxxing-dev";

const args = process.argv.slice(2);
const flag = (name, fallback = null) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 && args[i + 1] && !args[i + 1].startsWith("--") ? args[i + 1] : fallback;
};
const has = (name) => args.includes(`--${name}`);

// "90m" | "2h" | "3d" -> milliseconds
function parseSince(value) {
  const m = String(value ?? "2h").match(/^(\d+)\s*([mhd])$/i);
  if (!m) throw new Error(`bad --since "${value}" (use 90m, 2h, 3d)`);
  const n = Number(m[1]);
  const unit = { m: 60_000, h: 3_600_000, d: 86_400_000 }[m[2].toLowerCase()];
  return n * unit;
}

const sinceMs = parseSince(flag("since", "2h"));
const userFilter = flag("user");
const outPath = flag("out", "maxi-sessions.jsonl");
const printOnly = has("print");

const logs = new CloudWatchLogsClient({ region: REGION });

// App Runner log groups carry the service id, so discover rather than hardcode.
// Both the container and the Lambda can serve /maxi; collect from whichever exist.
async function findLogGroups() {
  const groups = [];
  for (const prefix of [`/aws/apprunner/${ENV_PREFIX}-api`, `/aws/lambda/${ENV_PREFIX}-api`]) {
    let nextToken;
    do {
      const out = await logs.send(
        new DescribeLogGroupsCommand({ logGroupNamePrefix: prefix, nextToken })
      );
      for (const g of out.logGroups ?? []) {
        // App Runner splits into /application and /service; only /application
        // carries our stdout.
        if (g.logGroupName.includes("/service")) continue;
        groups.push(g.logGroupName);
      }
      nextToken = out.nextToken;
    } while (nextToken);
  }
  return groups;
}

async function collect(logGroupName, startTime) {
  const records = [];
  let nextToken;
  do {
    const out = await logs.send(
      new FilterLogEventsCommand({
        logGroupName,
        startTime,
        filterPattern: '"maxi session"',
        nextToken,
      })
    );
    for (const e of out.events ?? []) {
      const at = e.message.indexOf("maxi session ");
      if (at < 0) continue;
      const jsonText = e.message.slice(at + "maxi session ".length).trim();
      try {
        records.push(JSON.parse(jsonText));
      } catch {
        // A truncated or interleaved line — skip rather than abort the pull.
      }
    }
    nextToken = out.nextToken;
  } while (nextToken);
  return records;
}

const startTime = Date.now() - sinceMs;
const groups = await findLogGroups();
if (!groups.length) {
  console.error(`no log groups found for ${ENV_PREFIX} — check AWS_PROFILE / ENV_PREFIX`);
  process.exit(1);
}

let all = [];
for (const g of groups) {
  const rows = await collect(g, startTime);
  console.error(`  ${g}: ${rows.length} turns`);
  all = all.concat(rows);
}

if (userFilter) all = all.filter((r) => r.userId === userFilter);
all.sort((a, b) => String(a.at).localeCompare(String(b.at)));

if (printOnly) {
  for (const r of all) {
    const acts = (r.actions ?? []).map((a) => `${a.type}(${a.n}${a.recipient ? `→${a.recipient}` : ""})`).join(" ");
    console.log(`\n─ ${r.at}  ${r.model?.split(".").pop()}  ${r.userId ?? "anon"}`);
    console.log(`  user  : ${r.user}`);
    console.log(`  maxi  : ${r.say}`);
    console.log(`  tools : ${(r.tools ?? []).join(", ") || "none"}`);
    console.log(`  acts  : ${acts || "none"}${r.reconciled ? "  [RECONCILED — model claimed without calling]" : ""}`);
    if (r.brief) console.log(`  brief : ${r.brief.recipient ?? "?"}${r.brief.occasion ? ` · ${r.brief.occasion}` : ""}`);
  }
  console.error(`\n${all.length} turns`);
} else {
  await writeFile(outPath, all.map((r) => JSON.stringify(r)).join("\n") + (all.length ? "\n" : ""));
  console.error(`wrote ${all.length} turns -> ${outPath}`);
}

// The signal worth watching: turns where Maxi CLAIMED a cart action.
const claims = all.filter((r) => /\b(cart|added)\b/i.test(r.say ?? ""));
const empty = claims.filter((r) => !(r.actions ?? []).some((a) => a.type === "add_to_cart"));
if (claims.length) {
  console.error(
    `cart-claiming turns: ${claims.length}  |  with NO add_to_cart action: ${empty.length}` +
      (empty.length ? "  <- these are the broken ones" : "")
  );
}
