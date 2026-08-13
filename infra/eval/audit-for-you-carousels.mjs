#!/usr/bin/env node
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

const api = (process.env.MIXER_API_URL || "https://d21osnvwewgoao.cloudfront.net").replace(/\/$/, "");
const manifest = JSON.parse(await readFile(resolve("Giftmaxxing/Resources/curated-gift-journeys.json"), "utf8"));
const expected = new Map(manifest.journeys.map((item) => [String(item.sourcePostId), item]));
const sources = Object.fromEntries(Object.entries({
  tiktok: manifest.journeys.filter(({ sourceUrl }) => sourceUrl.includes("tiktok.com")).length,
  wishwave: manifest.journeys.filter(({ sourceUrl }) => sourceUrl.includes("wishwave.com")).length,
  giftofflist: manifest.journeys.filter(({ sourceUrl }) => sourceUrl.includes("giftofflist.com")).length,
}).filter(([, count]) => count));
let cursor = null;
const pages = [], served = [];
for (let page = 1; page <= 10; page++) {
  const body = {
    surface: "home", context: { themeId: "for-you" },
    page: { limit: 40, ...(cursor ? { cursor } : {}) },
    session: { id: `carousel-exposure-${Date.now()}` },
  };
  const response = await fetch(`${api}/v2/recommendations`, {
    method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body),
  });
  if (!response.ok) throw new Error(`page ${page}: HTTP ${response.status}`);
  const data = await response.json();
  const carousels = data.items.filter(({ item }) => item.kind === "ugc_post").map(({ item }) => ({
    sourcePostId: item.entityId.replace("curated-source-", ""), title: item.title,
    cover: item.media?.[0]?.url ?? null,
  }));
  served.push(...carousels);
  pages.push({ page, items: data.items.length, carousels: carousels.length, nextCursor: Boolean(data.nextCursor), entries: carousels });
  cursor = data.nextCursor;
  if (!cursor) break;
}
const unique = new Map(served.map((item) => [item.sourcePostId, item]));
const report = {
  runAt: new Date().toISOString(), api,
  inventory: { total: expected.size, sources },
  exposure: { unique: unique.size, totalSlots: served.length, duplicates: served.length - unique.size, pages: pages.length },
  missing: [...expected.keys()].filter((id) => !unique.has(id)), pages,
};
const outDir = resolve("infra/eval/runs/carousel-exposure");
await mkdir(outDir, { recursive: true });
const path = resolve(outDir, "for-you.json");
await writeFile(path, `${JSON.stringify(report, null, 2)}\n`);
console.log(JSON.stringify({ path, inventory: report.inventory.total, exposed: report.exposure.unique, missing: report.missing.length, pages: report.exposure.pages }, null, 2));
