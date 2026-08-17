#!/usr/bin/env node
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

const reportPath = resolve(process.argv[2] || "infra/eval/runs/carousel-exposure/for-you.json");
const report = JSON.parse(await readFile(reportPath, "utf8"));
const outputDir = resolve("output/playwright/carousel-exposure");
await mkdir(outputDir, { recursive: true });
const cards = report.pages.flatMap((page) => page.entries.map((item) => ({ ...item, page: page.page })));
const media = (url) => url?.startsWith("/") ? `${report.api}${url}` : url;
const html = `<!doctype html><meta charset="utf-8"><title>For You carousel exposure</title>
<style>*{box-sizing:border-box}body{margin:0;background:#f2f4f5;color:#101820;font:14px -apple-system,BlinkMacSystemFont,sans-serif}.wrap{width:1280px;padding:28px}.head{display:flex;justify-content:space-between;align-items:end;margin-bottom:22px}.head h1{font-size:30px;margin:0 0 5px}.metric{font-size:18px;font-weight:750}.good{color:#078a86}.grid{display:grid;grid-template-columns:repeat(5,1fr);gap:16px}.card{background:white;border-radius:18px;overflow:hidden;box-shadow:0 3px 15px #18202812}.card img{width:100%;aspect-ratio:4/5;object-fit:cover;display:block;background:#e8ebed}.copy{padding:12px 13px 14px}.title{font-weight:750;line-height:1.22;min-height:34px}.meta{color:#6f7880;font-size:12px;margin-top:7px}</style>
<div class="wrap"><div class="head"><div><h1>For You · live carousel exposure</h1><div>Recommendation API snapshot · ${report.runAt}</div></div><div class="metric"><span class="good">${report.exposure.unique}/${report.inventory.total}</span> curated carousels shown · ${report.exposure.pages} pages · ${report.exposure.duplicates} duplicates</div></div><div class="grid">${cards.map((item) => `<article class="card"><img src="${media(item.cover)}"><div class="copy"><div class="title">${item.title}</div><div class="meta">API page ${item.page} · ${item.sourcePostId}</div></div></article>`).join("")}</div></div>`;
const path = resolve(outputDir, "for-you.html");
await writeFile(path, html);
console.log(path);
