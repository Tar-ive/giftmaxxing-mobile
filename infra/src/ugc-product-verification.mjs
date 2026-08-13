import { isIP } from "node:net";
import { lookup } from "node:dns/promises";

const MAX_IMAGES = 8;
const clean = (value, max = 280) => String(value ?? "")
  .replace(/<[^>]+>/g, " ")
  .replace(/&(?:nbsp|amp|quot|#39);/g, " ")
  .replace(/\s+/g, " ")
  .trim()
  .slice(0, max);

function safeUrl(value) {
  let url;
  try { url = new URL(value); } catch { return null; }
  if (url.protocol !== "https:") return null;
  const host = url.hostname.toLowerCase();
  if (host === "localhost" || host.endsWith(".local") || host.endsWith(".internal")) return null;
  if (host === "169.254.169.254" || host === "metadata.google.internal") return null;
  if (isIP(host) && /^(?:10\.|127\.|169\.254\.|192\.168\.|172\.(?:1[6-9]|2\d|3[01])\.)/.test(host)) return null;
  return url;
}

const isPrivateAddress = (address) => /^(?:10\.|127\.|169\.254\.|192\.168\.|172\.(?:1[6-9]|2\d|3[01])\.|0\.)/.test(address)
  || address === "::1" || address.startsWith("fc") || address.startsWith("fd") || address.startsWith("fe80:");

async function assertPublicHost(url, resolveHost) {
  if (isIP(url.hostname)) {
    if (isPrivateAddress(url.hostname)) throw new Error("private product host");
    return;
  }
  const addresses = await resolveHost(url.hostname, { all: true, verbatim: true });
  if (!addresses.length || addresses.some(({ address }) => isPrivateAddress(address))) throw new Error("private product host");
}

function productNodes(html) {
  const out = [];
  for (const match of html.matchAll(/<script[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)) {
    let data;
    try { data = JSON.parse(match[1]); } catch { continue; }
    for (const root of Array.isArray(data) ? data : [data]) {
      const nodes = [root, ...(Array.isArray(root?.["@graph"]) ? root["@graph"] : [])];
      out.push(...nodes.filter((node) => node && [].concat(node["@type"] ?? []).includes("Product")));
    }
  }
  return out;
}

function images(value) {
  const list = Array.isArray(value) ? value : value ? [value] : [];
  return [...new Set(list.map((item) => typeof item === "string" ? item : item?.url)
    .filter((url) => safeUrl(url)).map(String))].slice(0, MAX_IMAGES);
}

function facts(node) {
  const values = Array.isArray(node.additionalProperty) ? node.additionalProperty : [];
  return values.map((item) => clean(`${item?.name ?? ""}: ${item?.value ?? ""}`, 120)).filter(Boolean).slice(0, 12);
}

async function fetchHtml(start, fetchImpl, resolveHost) {
  let url = start;
  for (let redirect = 0; redirect < 4; redirect++) {
    const parsed = safeUrl(url);
    if (!parsed) throw new Error("unsafe product URL");
    await assertPublicHost(parsed, resolveHost);
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 12_000);
    let response;
    try {
      response = await fetchImpl(url, {
        redirect: "manual", signal: controller.signal,
        headers: { "user-agent": "Mozilla/5.0 GiftmaxxingProductVerifier/1.0", accept: "text/html,application/xhtml+xml" },
      });
    } finally { clearTimeout(timer); }
    if ([301, 302, 303, 307, 308].includes(response.status)) {
      const location = response.headers.get("location");
      if (!location) throw new Error("redirect without location");
      url = new URL(location, url).toString();
      continue;
    }
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    if (!String(response.headers.get("content-type") ?? "").includes("html")) throw new Error("source is not HTML");
    return { html: await response.text(), finalUrl: url };
  }
  throw new Error("too many redirects");
}

export async function verifyProductLink(link, { fetchImpl = fetch, resolveHost = lookup } = {}) {
  const requestedUrl = String(link?.url ?? "");
  if (!safeUrl(requestedUrl)) return { status: "SOURCE_REJECTED", requestedUrl, reason: "unsafe or invalid URL" };
  try {
    const { html, finalUrl } = await fetchHtml(requestedUrl, fetchImpl, resolveHost);
    const node = productNodes(html)[0];
    if (!node) return { status: "MANUAL_REVIEW_REQUIRED", requestedUrl, finalUrl, reason: "no Product structured data" };
    const offer = Array.isArray(node.offers) ? node.offers[0] : node.offers ?? {};
    const title = clean(node.name || link.name, 180);
    const description = clean(node.description, 220);
    const gallery = images(node.image);
    if (!title || !description || !gallery.length) {
      return { status: "MANUAL_REVIEW_REQUIRED", requestedUrl, finalUrl, reason: "incomplete product evidence" };
    }
    return {
      status: "EVIDENCE_READY",
      requestedUrl, finalUrl, title, description,
      brand: clean(typeof node.brand === "string" ? node.brand : node.brand?.name, 120) || undefined,
      images: gallery, features: facts(node),
      merchant: new URL(finalUrl).hostname.replace(/^www\./, ""),
      price: Number.isFinite(Number(offer.price)) ? Number(offer.price) : undefined,
      currency: clean(offer.priceCurrency, 8) || undefined,
      availability: clean(offer.availability, 120).split("/").pop() || undefined,
      evidenceSource: "retailer_jsonld", capturedAt: Date.now(),
    };
  } catch (error) {
    return { status: "MANUAL_REVIEW_REQUIRED", requestedUrl, reason: clean(error.message, 160) };
  }
}

export async function verifyProductLinks(links, deps) {
  return Promise.all((Array.isArray(links) ? links : []).slice(0, 8).map((link) => verifyProductLink(link, deps)));
}

export function productPipelineStatus(candidates, hadLinks) {
  if (candidates.some((item) => item.status === "EVIDENCE_READY")) return "EVIDENCE_READY";
  return hadLinks ? "MANUAL_REVIEW_REQUIRED" : "NEEDS_PRODUCT_SOURCE";
}
