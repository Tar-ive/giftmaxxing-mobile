import { createHash } from "node:crypto";

export const CATALOG_SCHEMA_VERSION = 2;
export const ITEM_KINDS = new Set(["product", "service", "ugc_post", "story", "generated_media"]);

const clean = (value, max = 500) => typeof value === "string" ? value.trim().slice(0, max) : "";
const num = (value) => Number.isFinite(Number(value)) ? Number(value) : null;
const list = (value, max = 24) => [...new Set((Array.isArray(value) ? value : []).map((x) => clean(x, 80).toLowerCase()).filter(Boolean))].slice(0, max);
const urls = (value, max = 12) => [...new Set((Array.isArray(value) ? value : []).map((x) => clean(x, 1200)).filter(Boolean))].slice(0, max);

export function inferItemKind(post = {}) {
  if (post.giftType === "service") return "service";
  if (post.source === "ugc" || post.ownerId || post.mediaType === "video") return "ugc_post";
  if (["story", "editorial", "gift_guide"].includes(post.contentType)) return "story";
  if (post.source === "ai" || post.generated === true) return "generated_media";
  return "product";
}

export function inferOrigin(post = {}) {
  const source = clean(post.source || post.author, 100).toLowerCase();
  if (source === "ugc" || post.ownerId) return { type: "ugc", provider: "giftmaxxing" };
  if (source.includes("shopify")) return { type: "retailer", provider: "shopify" };
  if (source.includes("catalog") || source.includes("amazon")) return { type: "retailer", provider: source || "catalog" };
  if (source.includes("instagram")) return { type: "scraped", provider: "instagram" };
  if (source.includes("pinterest") || String(post.postId || "").startsWith("pin-")) return { type: "scraped", provider: "pinterest" };
  if (source.includes("ai") || post.generated === true) return { type: "ai", provider: source || "giftmaxxing" };
  return { type: "editorial", provider: source || "giftmaxxing" };
}

export function normalizeLegacyPost(post = {}) {
  const id = clean(post.entityId || post.itemId || post.postId || post.id, 160);
  if (!id) throw new Error("item id required");
  const product = post.product ?? {};
  const kind = ITEM_KINDS.has(post.kind) ? post.kind : inferItemKind(post);
  const price = num(post.price ?? product.price);
  const url = clean(post.productUrl || post.url || product.url, 1000);
  const media = urls([post.mediaUrl, post.posterUrl, post.image, product.image, ...(product.images ?? []), ...(post.mediaUrls ?? [])].filter(Boolean), 12);
  const labels = list([...(post.vibes ?? []), post.category, post.recipient, post.occasion].filter(Boolean));
  const direct = (kind === "product" || kind === "service") && Boolean(url) && Number(price) > 0;
  const bridged = !direct && Array.isArray(post.shoppable) && post.shoppable.length > 0;
  const origin = inferOrigin(post);
  const title = clean(product.name || post.name || post.caption || "Gift idea", 240);
  const merchant = clean(post.merchant || product.brand || post.domain, 160);
  const features = list(post.capabilities ?? product.capabilities ?? [], 16);
  return {
    entityId: id,
    entityType: "item",
    schemaVersion: CATALOG_SCHEMA_VERSION,
    kind,
    status: post.feedEligible === false || post.status === "REJECTED" ? "restricted" : "active",
    title,
    summary: clean(post.shortDescription || post.story || post.caption, 1000),
    features,
    media: media.map((url, index) => ({ url, role: index === 0 ? "primary" : "gallery" })),
    creator: { id: clean(post.ownerId || post.author, 160), name: clean(post.authorName || post.author, 160) },
    provenance: {
      ...origin,
      sourceId: id,
      sourceUrl: clean(post.pinUrl || post.url, 1000),
      observedAt: num(post.createdAt) ?? Date.now(),
    },
    taxonomy: {
      primaryCategoryId: clean(post.category, 100).toLowerCase() || "uncategorized",
      labelIds: labels,
      assertions: labels.map((labelId) => ({ labelId, source: "legacy", confidence: 0.7, reviewStatus: "provisional" })),
    },
    commerce: {
      shoppability: direct ? "direct" : bridged ? "bridged" : "inspiration_only",
      offers: direct ? [{ offerId: `offer:${id}`, merchant, url, price, currency: "USD", availability: "unknown" }] : [],
    },
    quality: {
      score: num(post.qualityScore) ?? 0.5,
      moderation: post.moderationStatus || "unknown",
      giftable: post.feedEligible !== false,
      curationStatus: clean(post.curationStatus, 40) || undefined,
      curationCollectionId: clean(post.curationCollectionId, 80) || undefined,
      curationCollectionVersion: clean(post.curationCollectionVersion, 80) || undefined,
      mediaVerified: post.mediaVerified === true,
      mediaSource: clean(post.mediaSource, 40) || undefined,
      mediaVerifiedAt: clean(post.mediaVerifiedAt, 80) || undefined,
      descriptionSource: clean(post.descriptionSource, 40) || undefined,
    },
    embeddingKey: clean(post.embeddingKey || post.postId, 160) || id,
    legacyPost: post,
    updatedAt: Date.now(),
  };
}

export function sourceIdentity(record = {}) {
  const provider = clean(record.source?.provider || record.provenance?.provider || "unknown", 80).toLowerCase();
  const sourceId = clean(record.source?.recordId || record.provenance?.sourceId || record.postId || record.id, 200);
  if (!sourceId) throw new Error("source record id required");
  return `${provider}#${sourceId}`;
}

export function stableEntityId(record = {}) {
  if (record.entityId) return clean(record.entityId, 160);
  return `item_${createHash("sha256").update(sourceIdentity(record)).digest("hex").slice(0, 24)}`;
}
