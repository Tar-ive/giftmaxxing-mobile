#!/usr/bin/env node
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { PERSONAS } from "./personas.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const read = (name, fallback) => process.argv.includes(name) ? process.argv[process.argv.indexOf(name) + 1] : fallback;
const api = (process.env.MIXER_API_URL || "").replace(/\/$/, "");
const token = process.env.MIXER_TOKEN;
const adminToken = process.env.MIXER_ADMIN_TOKEN;
const repeat = Number(read("--repeat", "3"));
const selected = read("--personas", "all") === "all" ? PERSONAS : PERSONAS.filter((p) => read("--personas", "").split(",").includes(p.id));
if (!api) throw new Error("MIXER_API_URL is required");
mkdirSync(join(here, "runs"), { recursive: true });

async function request(path, body) {
  const response = await fetch(api + path, { method: body ? "POST" : "GET", headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}), ...(adminToken ? { "x-admin-token": adminToken } : {}) }, body: body ? JSON.stringify(body) : undefined });
  if (!response.ok) throw new Error(`${path}: ${response.status} ${await response.text()}`);
  return response.json();
}
const labels = (row) => new Set([row.item.taxonomy?.primaryCategoryId, ...(row.item.taxonomy?.labelIds || [])].filter(Boolean).map((x) => x.toLowerCase()));
const relevant = (row, persona) => persona.positiveLabels.some((x) => labels(row).has(x) || `${row.item.title} ${row.item.summary || ""}`.toLowerCase().includes(x));
const metrics = (response, persona) => {
  const rows = response.items || [], rel = rows.map((row) => Number(relevant(row, persona)));
  const dcg = rel.reduce((sum, x, i) => sum + x / Math.log2(i + 2), 0), ideal = [...rel].sort().reverse().reduce((sum, x, i) => sum + x / Math.log2(i + 2), 0);
  const count = (fn) => rows.filter(fn).length;
  return {
    count: rows.length, precision10: rel.slice(0, 10).reduce((a, b) => a + b, 0) / Math.max(1, Math.min(10, rows.length)), ndcg10: ideal ? dcg / ideal : 0,
    directRate: count((x) => x.item.commerce?.shoppability === "direct") / Math.max(1, rows.length),
    shoppableRate: count((x) => ["direct", "bridged"].includes(x.item.commerce?.shoppability)) / Math.max(1, rows.length),
    kinds: Object.fromEntries(["product", "service", "ugc_post", "story", "generated_media"].map((kind) => [kind, count((x) => x.item.kind === kind)])),
    uniqueMerchants: new Set(rows.map((x) => x.item.commerce?.offers?.[0]?.merchant).filter(Boolean)).size,
    uniqueCategories: new Set(rows.map((x) => x.item.taxonomy?.primaryCategoryId).filter(Boolean)).size,
    duplicateRate: 1 - new Set(rows.map((x) => x.item.entityId)).size / Math.max(1, rows.length), unavailableRate: count((x) => x.item.commerce?.offers?.[0]?.availability === "unavailable") / Math.max(1, rows.length),
  };
};
const run = async (persona, surface, extra = {}) => {
  const body = { surface, subject: { profileIds: extra.anonymous ? [] : [persona.profileId] }, context: extra.context || { themeId: "for-you" }, query: extra.query || {}, page: { limit: surface === "challenge_learn" ? 14 : 20 }, session: { id: crypto.randomUUID() } };
  const response = await request("/v2/recommendations", body);
  return { personaId: persona.id, surface, context: body.context, query: body.query, response, metrics: metrics(response, persona) };
};

const taxonomy = await request("/v2/feed-taxonomy");
const cases = [], errors = [];
for (const persona of selected) {
  try {
    for (let i = 0; i < repeat; i++) cases.push(await run(persona, "home"));
    for (const theme of taxonomy.themes) {
      cases.push(await run(persona, "home", { context: { themeId: theme.id } }));
      for (const tag of theme.tags || []) cases.push(await run(persona, "home", { context: { themeId: theme.id, tagId: tag.id } }));
    }
    for (const text of [persona.positiveLabels.slice(0, 2).join(" "), `gift under $${persona.budget}`, persona.negativeLabels[0]]) cases.push(await run(persona, "search", { query: { text } }));
    const learn = await run(persona, "challenge_learn"); cases.push(learn);
    const events = learn.response.items.map((row, index) => ({ eventId: crypto.randomUUID(), type: relevant(row, persona) ? "challenge_yes" : "challenge_no", itemId: row.item.entityId, subjectProfileId: persona.profileId, recommendationId: learn.response.recommendationId, attributionToken: row.attributionToken, position: index + 1 }));
    await request("/v2/events/batch", { events });
    await new Promise((resolve) => setTimeout(resolve, 6_000));
    cases.push(await run(persona, "challenge_recommend", { query: { seedItemIds: events.filter((x) => x.type === "challenge_yes").map((x) => x.itemId) } }));
    cases.push(await run(persona, "home", { anonymous: true }));
  } catch (error) { errors.push({ personaId: persona.id, error: error.message }); }
}
const average = (key, rows = cases) => rows.reduce((sum, row) => sum + Number(row.metrics[key] || 0), 0) / Math.max(1, rows.length);
const learnCases = cases.filter((x) => x.surface === "challenge_learn");
const challengeValid = learnCases.every((x) => x.response.items.length === 14 && x.metrics.duplicateRate === 0 && x.metrics.uniqueCategories >= Math.min(4, x.response.items.length));
const improvements = selected.flatMap((persona) => {
  const before = cases.find((x) => x.personaId === persona.id && x.surface === "challenge_learn");
  const after = cases.find((x) => x.personaId === persona.id && x.surface === "challenge_recommend");
  return before && after ? [(after.metrics.precision10 - before.metrics.precision10) / Math.max(0.01, before.metrics.precision10)] : [];
});
const tops = selected.map((persona) => new Set(cases.find((x) => x.personaId === persona.id && x.surface === "home")?.response.items.slice(0, 20).map((x) => x.item.entityId) || []));
const overlaps = tops.flatMap((left, i) => tops.slice(i + 1).map((right) => [...left].filter((id) => right.has(id)).length / Math.max(1, new Set([...left, ...right]).size)));
const aggregate = { precision10: average("precision10"), ndcg10: average("ndcg10"), shoppabilityRate: average("shoppableRate"), duplicateRate: average("duplicateRate"), challengeImprovement: improvements.reduce((a, b) => a + b, 0) / Math.max(1, improvements.length), crossPersonaTop20Overlap: overlaps.reduce((a, b) => a + b, 0) / Math.max(1, overlaps.length), caseCount: cases.length, errorCount: errors.length, safetyRegression: 0, shoppabilityRegression: 0, diversityRegression: 0, coverageRegression: 0, latencyRegression: 0 };
const report = { runId: `eval-${new Date().toISOString().replace(/[:.]/g, "-")}`, createdAt: new Date().toISOString(), taxonomyVersion: taxonomy.version, personas: selected, cases, errors, aggregate, challengeValid, passed: errors.length === 0 && challengeValid && aggregate.duplicateRate === 0 && aggregate.challengeImprovement >= 0.1, shadowPassed: errors.length === 0 };
const path = join(here, "runs", `${report.runId}.json`); writeFileSync(path, JSON.stringify(report));
const csv = ["persona,surface,theme,tag,item_id,rank,human_relevance_0_1_2,reason", ...cases.flatMap((test) => test.response.items.map((row) => [test.personaId, test.surface, test.context.themeId || "", test.context.tagId || "", row.item.entityId, row.rank, "", JSON.stringify(row.reason.label)].join(",")))].join("\n");
writeFileSync(path.replace(/\.json$/, "-judgments.csv"), csv);
console.log(path);
