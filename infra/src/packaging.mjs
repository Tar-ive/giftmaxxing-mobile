// Packaging plans — the pure half.
//
// POST /packaging turns one cart section (everything going to ONE person) into
// a wrap plan and a rendered picture of it. Everything here is deterministic
// and AWS-free so it can be unit-tested: the signature that makes repeat carts
// free, the prompts, and the normalizer that turns whatever the model actually
// returns into the shape the client expects.
//
// Why a signature and not a per-request render: image generation is the only
// genuinely expensive thing in this app (cents per image, seconds of latency).
// The same cart must produce the same picture, forever, for free.
import { createHash } from "node:crypto";

// Keep the plan small enough to read on a phone at 11pm.
const MAX_TITLE = 48;
const MAX_MATERIALS = 6;
const MAX_STEPS = 6;
const MIN_STEPS = 3;
const MAX_STEP_CHARS = 140;
const MAX_IMAGE_PROMPT = 600;
const PALETTE_SIZE = 3;

const clean = (v) => String(v ?? "").replace(/\s+/g, " ").trim();

/**
 * Stable identity for "this pile of gifts, for this occasion".
 * Order-independent (the cart reorders freely) and quantity-independent
 * (wrapping two of a thing is the same job as wrapping one).
 */
export function cartSignature(items, ctx = {}) {
  const ids = [...new Set((items ?? []).map((i) => clean(i?.postId)).filter(Boolean))].sort();
  const payload = JSON.stringify({
    ids,
    occasion: clean(ctx.occasion).toLowerCase(),
    relationship: clean(ctx.relationship).toLowerCase(),
  });
  return createHash("sha256").update(payload).digest("hex").slice(0, 32);
}

export const packagingCacheKey = (sig) => `packaging#${sig}`;

/**
 * Where the rendered image lives. Hex-only by construction, so a signature can
 * never escape the prefix.
 */
export function publicKeyFor(sig) {
  const safe = String(sig ?? "").replace(/[^a-f0-9]/gi, "").slice(0, 64);
  if (!safe) throw new Error("invalid packaging signature");
  return `wrap/public/${safe}.png`;
}

/** Same cart → same picture. Nova Canvas seeds are 0..2147483646. */
export function seedFrom(sig) {
  const hex = String(sig ?? "").replace(/[^a-f0-9]/gi, "").slice(0, 8) || "0";
  return parseInt(hex, 16) % 2147483646;
}

/**
 * What we ask the vision model. It is looking at the real product photos, so
 * the instruction is to describe wrapping THESE objects — sizes, shapes and
 * awkward bits — not to recite generic gift-wrap advice.
 */
export function buildVisionPrompt(items, ctx = {}) {
  const lines = (items ?? []).slice(0, 8).map((item, i) => {
    const parts = [clean(item?.title) || "a gift"];
    if (item?.category) parts.push(clean(item.category));
    if (typeof item?.price === "number" && item.price > 0) parts.push(`$${Math.round(item.price)}`);
    return `${i + 1}. ${parts.join(" · ")}`;
  });

  const context = [];
  if (ctx.recipientName) context.push(`They are for ${clean(ctx.recipientName)}.`);
  if (ctx.occasion) context.push(`The occasion is ${clean(ctx.occasion)}.`);
  if (ctx.relationship) context.push(`The giver's relationship to them: ${clean(ctx.relationship)}.`);

  return [
    "You are a gift-wrapping stylist. You are shown the actual items someone is giving to one person.",
    "Design ONE cohesive way to wrap and present them together.",
    "",
    "The items:",
    ...lines,
    ...(context.length ? ["", ...context] : []),
    "",
    "Rules:",
    "- Work with the real shapes and sizes you can see. Awkward items (mugs, bottles, soft goods) need specific handling — say what it is.",
    "- Materials must be things findable in a supermarket or craft shop. No custom or bespoke items.",
    "- Steps are physical actions, in order, one sentence each.",
    "- The palette must suit the products, not a generic holiday.",
    "- noteIdea is two sentences at most, warm and specific, written for the giver to copy.",
    "- imagePrompt describes the FINISHED wrapped presentation as a photograph. No text, no logos, no people, no hands.",
    "",
    "Reply with JSON only, no prose and no code fences:",
    '{"title":"","vibe":"","materials":[],"palette":["#hex","#hex","#hex"],"steps":[],"noteIdea":"","imagePrompt":""}',
  ].join("\n");
}

/**
 * The plan's imagePrompt, hardened for the renderer: brand names stripped
 * (generating a trademarked package is a liability we don't need), length
 * capped, and a fixed photographic style appended so results are consistent.
 */
export function buildCanvasPrompt(plan, brands = []) {
  let prompt = clean(plan?.imagePrompt);
  if (!prompt) {
    const materials = (plan?.materials ?? []).slice(0, 4).join(", ");
    prompt = `a wrapped gift presentation using ${materials || "kraft paper and ribbon"}`;
  }

  // Drop brand tokens from the item titles — the picture should show wrapping,
  // not a recognisable product package.
  for (const brand of brands) {
    const token = clean(brand);
    if (token.length < 3) continue;
    prompt = prompt.replace(new RegExp(escapeRegExp(token), "gi"), "").replace(/\s+/g, " ");
  }

  const styled = `${prompt.trim()}, overhead flat lay on a plain warm neutral surface, soft natural daylight, shallow depth of field, editorial product photography`;
  return styled.slice(0, MAX_IMAGE_PROMPT);
}

const escapeRegExp = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

const HEX = /^#[0-9a-f]{6}$/i;

/**
 * Models return JSON wrapped in prose, in code fences, with extra keys, with
 * nine steps, and occasionally with colour NAMES where hex was asked for.
 * Normalize all of it or return null so the caller can degrade honestly.
 */
export function normalizePlan(raw) {
  const parsed = parseLoose(raw);
  if (!parsed || typeof parsed !== "object") return null;

  const steps = asArray(parsed.steps)
    .map((s) => clean(s).slice(0, MAX_STEP_CHARS))
    .filter(Boolean)
    .slice(0, MAX_STEPS);
  if (steps.length < MIN_STEPS) return null; // fewer than three isn't a method

  const materials = asArray(parsed.materials)
    .map((m) => clean(m).slice(0, 40))
    .filter(Boolean)
    .slice(0, MAX_MATERIALS);

  const palette = asArray(parsed.palette)
    .map((c) => clean(c))
    .filter((c) => HEX.test(c))
    .slice(0, PALETTE_SIZE);

  return {
    title: clean(parsed.title).slice(0, MAX_TITLE) || "A way to wrap it",
    vibe: clean(parsed.vibe).slice(0, 120) || null,
    materials,
    palette,
    steps,
    noteIdea: clean(parsed.noteIdea).slice(0, 280) || null,
    imagePrompt: clean(parsed.imagePrompt).slice(0, MAX_IMAGE_PROMPT) || null,
  };
}

function asArray(v) {
  if (Array.isArray(v)) return v;
  if (typeof v === "string" && v.trim()) return v.split(/\n|;|·/);
  return [];
}

// Tolerate ```json fences, leading apologies, and trailing commentary.
function parseLoose(raw) {
  if (raw && typeof raw === "object") return raw;
  const text = String(raw ?? "");
  if (!text.trim()) return null;

  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
  const candidates = [fenced?.[1], sliceBraces(text), text];
  for (const candidate of candidates) {
    if (!candidate) continue;
    try {
      return JSON.parse(candidate);
    } catch {
      /* try the next shape */
    }
  }
  return null;
}

function sliceBraces(text) {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  return start >= 0 && end > start ? text.slice(start, end + 1) : null;
}
