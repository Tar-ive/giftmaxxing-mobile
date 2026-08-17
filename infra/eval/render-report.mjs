#!/usr/bin/env node
import { readFileSync, writeFileSync } from "node:fs";
const read = (name) => process.argv[process.argv.indexOf(name) + 1];
const path = read("--run"); if (!path) throw new Error("--run RUN.json is required");
const report = JSON.parse(readFileSync(path, "utf8"));
const esc = (x) => String(x ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const cards = report.cases.map((test) => `<section><h2>${esc(test.personaId)} · ${esc(test.surface)} · ${esc(test.context?.themeId)}</h2><p>P@10 ${test.metrics.precision10.toFixed(2)} · NDCG ${test.metrics.ndcg10.toFixed(2)} · shoppable ${(test.metrics.shoppableRate * 100).toFixed(0)}%</p><div class="grid">${test.response.items.map((row) => `<article><img src="${esc(row.item.media?.[0]?.url)}"><b>${esc(row.item.title)}</b><small>#${row.rank} · ${esc(row.item.kind)} · ${esc(row.reason.label)}</small></article>`).join("")}</div></section>`).join("");
const html = `<!doctype html><meta charset="utf-8"><title>${esc(report.runId)}</title><style>body{font:14px system-ui;margin:32px;background:#faf8f5;color:#241f1b}section{margin:36px 0}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(170px,1fr));gap:12px}article{background:white;border:1px solid #e5ded7;border-radius:12px;padding:10px;display:grid;gap:8px}img{width:100%;aspect-ratio:1;object-fit:cover;border-radius:8px}small{color:#746b64}</style><h1>${esc(report.runId)}</h1><pre>${esc(JSON.stringify(report.aggregate, null, 2))}</pre>${cards}`;
const out = path.replace(/\.json$/, ".html"); writeFileSync(out, html); console.log(out);
