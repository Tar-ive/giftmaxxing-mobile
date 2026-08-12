const text = (value, limit = 200) => typeof value === "string" ? value.trim().slice(0, limit) : "";
const number = (value) => Number.isFinite(Number(value)) && Number(value) > 0 ? Number(value) : undefined;
const list = (value, limit = 20) => Array.isArray(value)
  ? value.map((item) => text(String(item), 120)).filter(Boolean).slice(0, limit)
  : [];

/** @typedef {"memory_write"|"memory_read"|"calender_refer"|"calender_update"|"catalog_read"|"cart_write"|"cart_read"} MaxiToolName */

/** @type {readonly MaxiToolName[]} */
export const MAXI_TOOL_NAMES = Object.freeze([
  "memory_write",
  "memory_read",
  "calender_refer",
  "calender_update",
  "catalog_read",
  "cart_write",
  "cart_read",
]);

export const MAXI_TOOL_DEFINITIONS = Object.freeze([
  {
    name: "memory_write",
    description: "Save one durable preference or fact the user explicitly shared. Do not store transient requests.",
    schema: {
      type: "object", additionalProperties: false,
      properties: {
        fact: { type: "string" },
        kind: { type: "string", enum: ["preference", "semantic"] },
        recipientName: { type: "string" },
      },
      required: ["fact"],
    },
  },
  {
    name: "memory_read",
    description: "Recall durable user or recipient preferences before asking for information that may already be known.",
    schema: {
      type: "object", additionalProperties: false,
      properties: { query: { type: "string" }, limit: { type: "number" } },
    },
  },
  {
    name: "calender_refer",
    description: "Read upcoming saved occasions when timing, deadlines, birthdays, or anniversaries matter.",
    schema: {
      type: "object", additionalProperties: false,
      properties: { withinDays: { type: "number" } },
    },
  },
  {
    name: "calender_update",
    description: "Save a dated occasion only after the user provides or confirms its title and date.",
    schema: {
      type: "object", additionalProperties: false,
      properties: {
        title: { type: "string" }, date: { type: "string", description: "YYYY-MM-DD" }, recipientName: { type: "string" },
      },
      required: ["title", "date"],
    },
  },
  {
    name: "catalog_read",
    description: "Read only approved curated Giftmaxxing products. Use for every recommendation, price refinement, or request to identify products shown in a photo.",
    schema: {
      type: "object", additionalProperties: false,
      properties: {
        query: { type: "string" },
        postIds: { type: "array", items: { type: "string" } },
        maxPrice: { type: "number" },
        cheaperThan: { type: "number", description: "Strict upper price bound for cheaper alternatives" },
        category: { type: "string" },
        vibes: { type: "array", items: { type: "string" } },
        limit: { type: "number" },
      },
    },
  },
  {
    name: "cart_write",
    description: "Add exact catalog postIds to the app cart after the user explicitly asks. Never invent IDs.",
    schema: {
      type: "object", additionalProperties: false,
      properties: {
        postIds: { type: "array", items: { type: "string" } }, recipient: { type: "string" }, occasion: { type: "string" },
      },
      required: ["postIds"],
    },
  },
  {
    name: "cart_read",
    description: "Read the user's current cart before answering cart-relative questions, checking duplicates, or referring to existing items.",
    schema: { type: "object", additionalProperties: false, properties: {} },
  },
]);

export function normalizeMaxiToolInput(name, raw = {}) {
  if (!MAXI_TOOL_NAMES.includes(name)) return { ok: false, error: `unknown tool ${name}` };
  const input = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
  let value;
  switch (name) {
    case "memory_write":
      value = { fact: text(input.fact, 280), kind: ["preference", "semantic"].includes(input.kind) ? input.kind : "semantic", recipientName: text(input.recipientName, 60) || undefined };
      if (!value.fact) return { ok: false, error: "fact required" };
      break;
    case "memory_read":
      value = { query: text(input.query, 120) || undefined, limit: Math.min(Math.max(Math.round(number(input.limit) || 8), 1), 20) };
      break;
    case "calender_refer":
      value = { withinDays: Math.min(Math.max(Math.round(number(input.withinDays) || 90), 1), 365) };
      break;
    case "calender_update":
      value = { title: text(input.title, 80), date: text(input.date, 10), recipientName: text(input.recipientName, 60) || undefined };
      if (!value.title || !/^\d{4}-\d{2}-\d{2}$/.test(value.date)) return { ok: false, error: "title and YYYY-MM-DD date required" };
      break;
    case "catalog_read":
      value = {
        query: text(input.query, 200) || undefined,
        postIds: list(input.postIds),
        maxPrice: number(input.maxPrice),
        cheaperThan: number(input.cheaperThan),
        category: text(input.category, 80) || undefined,
        vibes: list(input.vibes, 10),
        limit: Math.min(Math.max(Math.round(number(input.limit) || 6), 1), 10),
      };
      break;
    case "cart_write":
      value = { postIds: list(input.postIds), recipient: text(input.recipient, 60) || undefined, occasion: text(input.occasion, 80) || undefined };
      if (!value.postIds.length) return { ok: false, error: "postIds required" };
      break;
    case "cart_read":
      value = {};
      break;
  }
  return { ok: true, value };
}

export const isCheaperRequest = (message) => /\b(cheaper|less expensive|lower[- ]priced?|more affordable|budget option)\b/i.test(String(message || ""));

export function shownProductPriceCeiling(products) {
  const prices = (Array.isArray(products) ? products : []).map((item) => number(item?.price)).filter(Boolean);
  return prices.length ? Math.min(...prices) : undefined;
}

export function effectiveCatalogPrice(input = {}, contextualCeiling) {
  const limits = [number(input.maxPrice), number(input.cheaperThan), number(contextualCeiling)].filter(Boolean);
  return limits.length ? Math.min(...limits) : undefined;
}
