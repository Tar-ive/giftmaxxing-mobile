import { createHmac, randomUUID, timingSafeEqual } from "node:crypto";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  BatchGetCommand,
  BatchWriteCommand,
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  QueryCommand,
  ScanCommand,
} from "@aws-sdk/lib-dynamodb";
import { BedrockRuntimeClient, InvokeModelCommand } from "@aws-sdk/client-bedrock-runtime";
import { GetVectorsCommand, QueryVectorsCommand, S3VectorsClient } from "@aws-sdk/client-s3vectors";
import { S3Client } from "@aws-sdk/client-s3";
import { normalizeLegacyPost, sourceIdentity, stableEntityId } from "./catalog-v2.mjs";
import { FEED_TAXONOMY, TAXONOMY_VERSION, resolveFeedContext } from "./feed-taxonomy.mjs";
import { POLICY_VERSION, mixCandidates, recommendationReason, scoreCandidate } from "./recommender-policies.mjs";
import { classifyPin } from "./quality.mjs";
import { activeRecommenderModel, modelProbability } from "./recommender-model.mjs";

const SURFACES = new Set(["home", "search", "challenge_learn", "challenge_recommend"]);
const EVENT_TYPES = new Set([
  "impression", "dwell", "search_tap", "like", "comment", "save", "hide", "offer_click", "purchase",
  "challenge_yes", "challenge_no", "challenge_uncertain",
  "reliability_reliable", "reliability_questionable",
]);
const VECTOR_DIM = Number(process.env.VECTOR_DIM || 1024);
const EMBED_MODEL = process.env.BEDROCK_EMBED_MODEL_ID || "amazon.titan-embed-image-v1";
const VECTOR_BUCKET = process.env.VECTOR_BUCKET || "";
const VECTOR_INDEX = process.env.VECTOR_INDEX || "pins";
const CURATED_RECOMMENDER_ONLY = process.env.CURATED_RECOMMENDER_ONLY !== "0";
const CURATION_COLLECTION_ID = "giftmaxxing-reviewed";
const CURATION_POINTER_ID = `curation_collection:${CURATION_COLLECTION_ID}`;
const TABLES = {
  entities: process.env.CATALOG_ENTITIES_TABLE,
  edges: process.env.CATALOG_EDGES_TABLE,
  profiles: process.env.TASTE_PROFILES_TABLE,
  posts: process.env.POSTS_TABLE,
  interactions: process.env.INTERACTIONS_TABLE,
  analytics: process.env.ANALYTICS_TABLE,
};

const defaultDeps = {
  ddb: DynamoDBDocumentClient.from(new DynamoDBClient({}), { marshallOptions: { removeUndefinedValues: true } }),
  s3v: VECTOR_BUCKET ? new S3VectorsClient({}) : null,
  bedrock: new BedrockRuntimeClient({}),
  s3: new S3Client({}),
  tables: TABLES,
};

const json = (statusCode, body, headers = {}) => ({
  statusCode,
  headers: { "content-type": "application/json", ...headers },
  body: JSON.stringify(body),
});
const clamp = (n, min, max) => Math.max(min, Math.min(max, Number(n) || min));
const boundedString = (value, max = 200) => typeof value === "string" ? value.trim().slice(0, max) : "";
const encodeCursor = (offset) => Buffer.from(JSON.stringify({ offset })).toString("base64url");
const decodeCursor = (cursor) => {
  try { return Math.max(0, Number(JSON.parse(Buffer.from(cursor, "base64url").toString()).offset) || 0); }
  catch { return 0; }
};

export function validateMixerRequest(body = {}) {
  const surface = SURFACES.has(body.surface) ? body.surface : null;
  if (!surface) throw new Error("surface must be home, search, challenge_learn, or challenge_recommend");
  const profileIds = [...new Set((body.subject?.profileIds ?? []).map((x) => boundedString(x, 160)).filter(Boolean))].slice(0, 5);
  const limitDefault = surface === "challenge_learn" ? 14 : 20;
  return {
    surface,
    profileIds,
    blend: body.subject?.blend === "group" ? "group" : "individual",
    context: {
      themeId: boundedString(body.context?.themeId || "for-you", 80),
      tagId: boundedString(body.context?.tagId, 80) || null,
      occasionId: boundedString(body.context?.occasionId, 80) || null,
    },
    query: {
      text: boundedString(body.query?.text, 200),
      imageBase64: boundedString(body.query?.imageBase64, 5_000_000),
      seedItemIds: [...new Set((body.query?.seedItemIds ?? []).map((x) => boundedString(x, 160)).filter(Boolean))].slice(0, 20),
    },
    constraints: {
      categoryIds: [...new Set((body.constraints?.categoryIds ?? []).map((x) => boundedString(x, 100).toLowerCase()).filter(Boolean))],
      labelIds: [...new Set((body.constraints?.labelIds ?? []).map((x) => boundedString(x, 100).toLowerCase()).filter(Boolean))],
      kinds: [...new Set((body.constraints?.kinds ?? []).map((x) => boundedString(x, 40)).filter(Boolean))],
      curatedOnly: body.constraints?.curatedOnly === true,
      minPrice: Number(body.constraints?.price?.min) || null,
      maxPrice: Number(body.constraints?.price?.max) || null,
      currency: boundedString(body.constraints?.price?.currency || "USD", 8),
    },
    page: { limit: clamp(body.page?.limit ?? limitDefault, 1, 50), offset: decodeCursor(body.page?.cursor) },
    session: {
      id: boundedString(body.session?.id || randomUUID(), 120),
      excludeItemIds: new Set((body.session?.excludeItemIds ?? []).map((x) => boundedString(x, 160)).filter(Boolean)),
    },
  };
}

function mergeProfiles(profiles) {
  if (!profiles.length) return { profileVersion: 0, labelWeights: {}, positiveItemIds: [], negativeItemIds: [], uncertainty: {} };
  const merged = { profileVersion: 0, labelWeights: {}, positiveItemIds: [], negativeItemIds: [], uncertainty: {} };
  for (const profile of profiles) {
    merged.profileVersion = Math.max(merged.profileVersion, Number(profile.version) || 0);
    for (const [label, weight] of Object.entries(profile.labelWeights ?? {})) merged.labelWeights[label] = (merged.labelWeights[label] || 0) + Number(weight || 0) / profiles.length;
    for (const [label, value] of Object.entries(profile.uncertainty ?? {})) merged.uncertainty[label] = Math.max(merged.uncertainty[label] || 0, Number(value || 0));
    merged.positiveItemIds.push(...(profile.positiveItemIds ?? []));
    merged.negativeItemIds.push(...(profile.negativeItemIds ?? []));
  }
  merged.positiveItemIds = [...new Set(merged.positiveItemIds)].slice(0, 24);
  merged.negativeItemIds = [...new Set(merged.negativeItemIds)].slice(0, 24);
  return merged;
}

async function loadProfiles(deps, profileIds, auth) {
  if (!profileIds.length || !deps.tables.profiles) return { ok: true, profile: mergeProfiles([]), ids: [] };
  const result = await deps.ddb.send(new BatchGetCommand({
    RequestItems: { [deps.tables.profiles]: { Keys: profileIds.map((profileId) => ({ profileId })) } },
  }));
  const profiles = result.Responses?.[deps.tables.profiles] ?? [];
  const actor = auth?.sub;
  const allowed = profiles.filter((profile) => auth?.via === "admin" || profile.ownerId === actor || (profile.authorizedViewerIds ?? []).includes(actor));
  if (allowed.length !== profileIds.length) return { ok: false, statusCode: actor ? 403 : 401 };
  return { ok: true, profile: mergeProfiles(allowed), ids: profileIds };
}

async function loadActiveCuration(deps) {
  if (!deps.tables.entities) return null;
  const result = await deps.ddb.send(new GetCommand({
    TableName: deps.tables.entities,
    Key: { entityId: CURATION_POINTER_ID },
    ConsistentRead: true,
  }));
  const version = boundedString(result.Item?.activeVersion, 80);
  const itemIds = [...new Set((result.Item?.itemIds ?? []).map((id) => boundedString(id, 160)).filter(Boolean))];
  return version && itemIds.length ? { collectionId: CURATION_COLLECTION_ID, version, itemIds } : null;
}

async function embed(deps, { text, imageBase64 }) {
  if (!text && !imageBase64) return null;
  const request = { embeddingConfig: { outputEmbeddingLength: VECTOR_DIM } };
  if (text) request.inputText = text.slice(0, 200);
  if (imageBase64) request.inputImage = imageBase64.replace(/^data:image\/[a-z0-9.+-]+;base64,/i, "");
  const output = await deps.bedrock.send(new InvokeModelCommand({
    modelId: EMBED_MODEL,
    contentType: "application/json",
    accept: "application/json",
    body: JSON.stringify(request),
  }));
  return JSON.parse(Buffer.from(output.body).toString("utf8")).embedding ?? null;
}

async function centroid(deps, keys) {
  if (!deps.s3v || !keys.length) return null;
  const result = await deps.s3v.send(new GetVectorsCommand({
    vectorBucketName: VECTOR_BUCKET, indexName: VECTOR_INDEX, keys: keys.slice(0, 20), returnData: true,
  }));
  const vectors = (result.vectors ?? []).map((v) => v.data?.float32).filter(Array.isArray);
  if (!vectors.length) return null;
  const sum = new Array(vectors[0].length).fill(0);
  for (const vector of vectors) for (let i = 0; i < sum.length; i++) sum[i] += vector[i];
  return sum.map((value) => value / vectors.length);
}

function averageVectors(vectors) {
  const valid = vectors.filter(Array.isArray);
  if (!valid.length) return null;
  const sum = new Array(valid[0].length).fill(0);
  for (const vector of valid) for (let i = 0; i < sum.length; i++) sum[i] += vector[i];
  return sum.map((value) => value / valid.length);
}

async function loadEntityMap(deps, ids) {
  if (!deps.tables.entities || !ids.length) return new Map();
  const output = new Map();
  for (let i = 0; i < ids.length; i += 100) {
    const result = await deps.ddb.send(new BatchGetCommand({
      RequestItems: { [deps.tables.entities]: { Keys: ids.slice(i, i + 100).map((entityId) => ({ entityId })) } },
    }));
    for (const item of result.Responses?.[deps.tables.entities] ?? []) output.set(item.entityId, item);
  }
  return output;
}

function vectorAsLegacy(vector) {
  const m = vector.metadata ?? {};
  return {
    postId: vector.key,
    name: m.title || "Gift idea",
    product: { name: m.title || "Gift idea", brand: m.domain || m.sourceUser || "", price: Number(m.price) || 0, image: m.imageUrl || "" },
    image: m.imageUrl || "",
    productUrl: m.link || m.pinUrl || "",
    url: m.link || m.pinUrl || "",
    category: m.category || "uncategorized",
    vibes: Array.isArray(m.vibes) ? m.vibes : [],
    source: m.source || "pinterest",
    giftType: m.giftType || "product",
    qualityScore: 0.7,
    feedEligible: true,
    createdAt: Number(m.createdAt) || Date.now(),
  };
}

async function vectorCandidates(deps, request, profile, terms) {
  if (!deps.s3v || !VECTOR_BUCKET) return [];
  const [queryVector, seedVector] = await Promise.all([
    embed(deps, { text: [request.query.text, ...terms].filter(Boolean).join(" "), imageBase64: request.query.imageBase64 }).catch(() => null),
    centroid(deps, [...request.query.seedItemIds, ...(profile.positiveItemIds ?? [])]).catch(() => null),
  ]);
  const combined = averageVectors([queryVector, seedVector]);
  if (!combined) return [];
  const output = await deps.s3v.send(new QueryVectorsCommand({
    vectorBucketName: VECTOR_BUCKET,
    indexName: VECTOR_INDEX,
    topK: 100,
    queryVector: { float32: combined },
    returnMetadata: true,
    returnDistance: true,
  }));
  const rows = output.vectors ?? [];
  const entities = await loadEntityMap(deps, rows.map((row) => row.key));
  return rows.map((row) => ({
    item: entities.get(row.key) ?? normalizeLegacyPost(vectorAsLegacy(row)),
    relevance: row.distance == null ? 0.5 : Math.max(0, 1 - Number(row.distance)),
    taste: seedVector && row.distance != null ? Math.max(0, 1 - Number(row.distance)) : undefined,
    source: "vector",
  }));
}

async function catalogCandidates(deps, limit = 600) {
  if (deps.tables.entities) {
    try {
      const perKind = { product: limit, service: 100, ugc_post: 100, story: 100, generated_media: 100 };
      const results = await Promise.all(Object.entries(perKind).map(([kind, kindLimit]) => deps.ddb.send(new QueryCommand({
        TableName: deps.tables.entities,
        IndexName: "byKind",
        KeyConditionExpression: "#kind = :kind AND #status = :active",
        ExpressionAttributeNames: { "#kind": "kind", "#status": "status" },
        ExpressionAttributeValues: { ":kind": kind, ":active": "active" },
        Limit: kindLimit,
      }))));
      const items = results.flatMap((result) => result.Items ?? []);
      if (items.length) return items.map((item) => ({ item, source: "catalog" }));
    } catch (error) {
      console.warn("v2 kind retrieval failed; falling back to scan", error.message);
    }
    const result = await deps.ddb.send(new ScanCommand({
      TableName: deps.tables.entities,
      FilterExpression: "entityType = :item AND #status = :active",
      ExpressionAttributeNames: { "#status": "status" },
      ExpressionAttributeValues: { ":item": "item", ":active": "active" },
      Limit: limit,
    }));
    if (result.Items?.length) return result.Items.map((item) => ({ item, source: "catalog" }));
  }
  if (!deps.tables.posts) return [];
  let rows = [];
  try {
    const result = await deps.ddb.send(new QueryCommand({
      TableName: deps.tables.posts,
      IndexName: "byFeed",
      KeyConditionExpression: "feedPk = :feed",
      ExpressionAttributeValues: { ":feed": "all" },
      ScanIndexForward: false,
      Limit: limit,
    }));
    rows = result.Items ?? [];
  } catch {
    const result = await deps.ddb.send(new ScanCommand({ TableName: deps.tables.posts, Limit: limit }));
    rows = result.Items ?? [];
  }
  return rows.flatMap((post) => {
    const product = post.product ?? {};
    const quality = classifyPin({
      title: product.name || post.name || post.caption,
      domain: post.domain || product.brand,
      link: post.productUrl || post.url || product.url,
      price: post.price ?? product.price,
      giftType: post.giftType,
    });
    if (!quality.feedEligible) return [];
    const item = normalizeLegacyPost({ ...post, feedEligible: true, qualityScore: post.qualityScore ?? quality.score });
    return [{ item, source: "legacy-catalog" }];
  });
}

async function curatedCandidates(deps, activeCuration) {
  if (!activeCuration) return [];
  const items = await loadEntityMap(deps, activeCuration.itemIds);
  return activeCuration.itemIds.flatMap((id) => items.has(id) ? [{ item: items.get(id), source: "curated-catalog" }] : []);
}

function informationGain(item, profile) {
  const labels = item.taxonomy?.labelIds ?? [];
  if (!labels.length) return 0.5;
  const uncertainty = profile.uncertainty ?? {};
  const weights = profile.labelWeights ?? {};
  return labels.reduce((sum, label) => {
    const explicit = Number(uncertainty[label]);
    return sum + (Number.isFinite(explicit) ? explicit : 1 / (1 + Math.abs(Number(weights[label]) || 0)));
  }, 0) / labels.length;
}

function passesCuratedBoundary(item, activeCuration) {
  return Boolean(activeCuration)
    && item.quality?.curationStatus === "approved"
    && item.quality?.curationCollectionId === activeCuration.collectionId
    && item.quality?.curationCollectionVersion === activeCuration.version
    && item.provenance?.provider === "giftmaxxing-curation";
}

function passesConstraints(item, constraints, feedContext, activeCuration, curatedRequired) {
  const offer = item.commerce?.offers?.[0];
  const price = Number(offer?.price);
  if (constraints.kinds.length && !constraints.kinds.includes(item.kind)) return false;
  if (curatedRequired && !passesCuratedBoundary(item, activeCuration)) return false;
  if (constraints.categoryIds.length && !constraints.categoryIds.includes(item.taxonomy?.primaryCategoryId)) return false;
  if (constraints.labelIds.length && !constraints.labelIds.some((label) => item.taxonomy?.labelIds?.includes(label))) return false;
  if (feedContext.theme.id !== "for-you") {
    const haystack = `${item.title ?? ""} ${item.summary ?? ""} ${item.taxonomy?.primaryCategoryId ?? ""} ${(item.taxonomy?.labelIds ?? []).join(" ")}`.toLowerCase();
    if (!feedContext.matchTerms.some((term) => haystack.includes(String(term).toLowerCase()))) return false;
  }
  const minPrice = constraints.minPrice ?? feedContext.minPrice;
  const maxPrice = constraints.maxPrice ?? feedContext.maxPrice;
  if (minPrice != null && (!Number.isFinite(price) || price < minPrice)) return false;
  if (maxPrice != null && (!Number.isFinite(price) || price > maxPrice)) return false;
  return item.status === "active" && item.quality?.giftable !== false;
}

function passesSurfacePolicy(item, surface) {
  if (!["challenge_learn", "challenge_recommend"].includes(surface)) return true;
  return item.kind === "product"
    && item.commerce?.shoppability === "direct"
    && item.quality?.mediaVerified === true
    && item.quality?.mediaSource === "retailer_listing"
    && item.media?.some(({ url }) => /^https?:\/\//i.test(url) || url.startsWith("/curated/"));
}

function signedAttribution(recommendationId, entityId, rank) {
  const secret = process.env.RECOMMENDER_ATTRIBUTION_SECRET || process.env.SESSION_JWT_SECRET || "local-development";
  const payload = `${recommendationId}.${entityId}.${rank}`;
  return `${Buffer.from(payload).toString("base64url")}.${createHmac("sha256", secret).update(payload).digest("base64url")}`;
}

function publicItem(item) {
  const { legacyPost: _legacyPost, sourceKey: _sourceKey, ...safe } = item;
  return safe;
}

function validAttribution(token, recommendationId, entityId, rank) {
  if (!token || !recommendationId || !rank) return false;
  const expected = signedAttribution(recommendationId, entityId, rank);
  const left = Buffer.from(token), right = Buffer.from(expected);
  return left.length === right.length && timingSafeEqual(left, right);
}

async function recommend(deps, body, auth) {
  let request;
  try { request = validateMixerRequest(body); }
  catch (error) { return json(400, { error: error.message }); }
  if (!request.profileIds.length && auth?.sub && auth.via !== "admin") request.profileIds = [`taste:${auth.sub}`];
  const loaded = await loadProfiles(deps, request.profileIds, auth);
  if (!loaded.ok) return json(loaded.statusCode, { error: "subject profile is not authorized" });

  const feedContext = resolveFeedContext(request.context.themeId, request.context.tagId);
  const terms = [...new Set([...feedContext.terms, ...request.query.text.toLowerCase().split(/\s+/).filter(Boolean)])];
  const curatedRequired = CURATED_RECOMMENDER_ONLY
    || request.constraints.curatedOnly
    || ["challenge_learn", "challenge_recommend"].includes(request.surface);
  const activeCuration = curatedRequired
    ? await loadActiveCuration(deps).catch((error) => { console.warn("active curation lookup failed", error.message); return null; })
    : null;
  const [vectors, catalog, activeModel] = await Promise.all([
    vectorCandidates(deps, request, loaded.profile, terms).catch((error) => { console.warn("v2 vector retrieval failed", error.message); return []; }),
    curatedRequired ? curatedCandidates(deps, activeCuration) : catalogCandidates(deps),
    activeRecommenderModel(deps),
  ]);
  const excluded = request.session.excludeItemIds;
  const scored = [...vectors, ...catalog]
    .filter(({ item }) => !excluded.has(item.entityId)
      && passesConstraints(item, request.constraints, feedContext, activeCuration, curatedRequired)
      && passesSurfacePolicy(item, request.surface))
    .map((candidate) => scoreCandidate({
      ...candidate,
      informationGain: request.surface === "challenge_learn" ? informationGain(candidate.item, loaded.profile) : candidate.informationGain,
    }, { surface: request.surface, terms, profile: loaded.profile }))
    .map((candidate) => {
      const learned = modelProbability(activeModel, candidate, loaded.profile);
      return learned == null ? candidate : { ...candidate, modelScore: learned, score: candidate.score * 0.8 + learned * 0.2 };
    });
  const ranked = mixCandidates(scored, { surface: request.surface, limit: request.page.offset + request.page.limit });
  const page = ranked.slice(request.page.offset, request.page.offset + request.page.limit);
  const recommendationId = `rec_${randomUUID()}`;
  const items = page.map((candidate, index) => {
    const rank = request.page.offset + index + 1;
    return {
      item: publicItem(candidate.item),
      rank,
      reason: recommendationReason(candidate, request.surface),
      attributionToken: signedAttribution(recommendationId, candidate.item.entityId, rank),
      source: candidate.source,
      ...(body.debug && auth?.via === "admin" ? { score: candidate.score, components: candidate.components } : {}),
    };
  });
  return json(200, {
    recommendationId,
    surface: request.surface,
    policyVersion: POLICY_VERSION,
    modelVersion: activeModel?.model && activeModel?.version ? `registry:${activeModel.version}` : "deterministic-cosine-v1",
    taxonomyVersion: TAXONOMY_VERSION,
    curationVersion: activeCuration?.version ?? null,
    profileVersion: loaded.profile.profileVersion,
    items,
    nextCursor: page.length === request.page.limit ? encodeCursor(request.page.offset + page.length) : null,
    cache: { key: createHmac("sha256", POLICY_VERSION).update(JSON.stringify({ ...body, page: undefined, curationVersion: activeCuration?.version })).digest("hex").slice(0, 24), staleAfterSeconds: 900 },
    ...(body.debug && auth?.via === "admin" ? { supply: supplyMetrics(scored), candidateCount: scored.length } : {}),
  }, { "cache-control": request.profileIds.length ? "private, no-store" : "public, max-age=60" });
}

function supplyMetrics(candidates) {
  const items = candidates.map((candidate) => candidate.item);
  const count = (fn) => items.filter(fn).length;
  return {
    total: items.length,
    direct: count((item) => item.commerce?.shoppability === "direct"),
    bridged: count((item) => item.commerce?.shoppability === "bridged"),
    ugc: count((item) => item.kind === "ugc_post"),
    stories: count((item) => ["story", "generated_media"].includes(item.kind)),
  };
}

async function getItem(deps, path) {
  const entityId = decodeURIComponent(path.split("/")[3] || "");
  if (!entityId) return json(400, { error: "item id required" });
  if (deps.tables.entities) {
    const result = await deps.ddb.send(new GetCommand({ TableName: deps.tables.entities, Key: { entityId } }));
    if (result.Item?.entityType === "item" && result.Item.status === "active") return json(200, { item: publicItem(result.Item) });
  }
  if (deps.tables.posts) {
    const result = await deps.ddb.send(new GetCommand({ TableName: deps.tables.posts, Key: { postId: entityId } }));
    if (result.Item) return json(200, { item: publicItem(normalizeLegacyPost(result.Item)) });
  }
  return json(404, { error: "not found" });
}

async function recordEvents(deps, body, auth) {
  if (!deps.tables.analytics) return json(503, { error: "event store not configured" });
  const events = Array.isArray(body.events) ? body.events.slice(0, 100) : [];
  if (!events.length) return json(400, { error: "events required" });
  const now = Date.now();
  const rows = events.map((event) => {
    const type = boundedString(event.type, 40);
    const eventId = boundedString(event.eventId || randomUUID(), 80);
    const timestamp = Number(event.timestamp) || now;
    const actorId = auth?.sub && auth.via !== "admin" ? auth.sub : boundedString(event.anonymousId || body.anonymousId || "anonymous", 160);
    const subjectProfileId = boundedString(event.subjectProfileId || `taste:${actorId}`, 160);
    const itemId = boundedString(event.itemId, 160);
    const recommendationId = boundedString(event.recommendationId, 160);
    const position = Number(event.position) || undefined;
    if (!EVENT_TYPES.has(type) || !eventId || !itemId) return null;
    if (event.attributionToken && !validAttribution(event.attributionToken, recommendationId, itemId, position)) return null;
    return {
      userId: actorId,
      sk: `${timestamp}#${eventId}`,
      eventId,
      schemaVersion: 2,
      type: `recommender_${type}`,
      timestamp,
      subjectProfileId,
      postId: boundedString(event.itemId, 160),
      itemId: boundedString(event.itemId, 160),
      recommendationId,
      attributionToken: boundedString(event.attributionToken, 1000),
      position,
      dwellMs: Number(event.dwellMs) || undefined,
      context: typeof event.context === "object" ? event.context : undefined,
      expiresAt: Math.floor(timestamp / 1000) + 180 * 86400,
    };
  }).filter(Boolean);
  if (!rows.length) return json(400, { error: "no valid events" });
  for (let i = 0; i < rows.length; i += 25) {
    await deps.ddb.send(new BatchWriteCommand({
      RequestItems: { [deps.tables.analytics]: rows.slice(i, i + 25).map((Item) => ({ PutRequest: { Item } })) },
    }));
  }
  return json(202, { ok: true, accepted: rows.length });
}

const RECIPIENT_ALIASES = {
  women: ["women", "woman", "girls", "girl", "her", "wife", "girlfriend", "mom", "mother", "sister", "daughter"],
  men: ["men", "man", "boys", "boy", "him", "husband", "boyfriend", "dad", "father", "brother", "son"],
  kids: ["kids", "kid", "child", "children", "daughter", "son", "girl", "boy"],
  partner: ["partner", "wife", "husband", "girlfriend", "boyfriend"],
  friend: ["friend", "best friend", "coworker"],
};

function recipientMatches(context, segment) {
  const value = String(context?.recipientSegment || context?.recipient || "").toLowerCase();
  return (RECIPIENT_ALIASES[segment] || [segment]).some((alias) => value.includes(alias));
}

async function recipientLeaderboard(deps, body) {
  const segment = boundedString(body.segment || "women", 40).toLowerCase();
  const limit = clamp(body.limit || 10, 1, 20);
  if (!Object.hasOwn(RECIPIENT_ALIASES, segment)) return json(400, { error: "unsupported recipient segment" });
  let rows = [];
  if (deps.tables.analytics) {
    const after = Date.now() - 90 * 86400_000;
    for (const type of ["recommender_challenge_yes", "recommender_like", "swipe_right"]) {
      try {
        const result = await deps.ddb.send(new QueryCommand({
          TableName: deps.tables.analytics, IndexName: "byType",
          KeyConditionExpression: "#type = :type AND #timestamp >= :after",
          ExpressionAttributeNames: { "#type": "type", "#timestamp": "timestamp" },
          ExpressionAttributeValues: { ":type": type, ":after": after }, Limit: 1000,
        }));
        rows.push(...(result.Items || []));
      } catch (error) { console.warn("recipient leaderboard query failed", error.message); }
    }
  }
  const counts = new Map();
  for (const row of rows) {
    if (!row.postId || !recipientMatches(row.context, segment)) continue;
    const current = counts.get(row.postId) || { itemId: row.postId, likes: 0, users: new Set() };
    current.likes += 1; current.users.add(row.userId); counts.set(row.postId, current);
  }
  const ranked = [...counts.values()].sort((a, b) => b.likes - a.likes).slice(0, limit);
  const entities = await loadEntityMap(deps, ranked.map((row) => row.itemId));
  let items = ranked.map((row, index) => ({
    rank: index + 1, score: row.likes, voterCount: row.users.size,
    item: entities.has(row.itemId) ? publicItem(entities.get(row.itemId)) : null,
  })).filter((row) => row.item);
  if (!items.length) {
    const active = await loadActiveCuration(deps).catch(() => null);
    const fallback = await curatedCandidates(deps, active);
    items = fallback
      .filter(({ item }) => (RECIPIENT_ALIASES[segment] || []).some((term) => `${item.title} ${(item.taxonomy?.labelIds || []).join(" ")}`.toLowerCase().includes(term)))
      .slice(0, limit)
      .map(({ item }, index) => ({ rank: index + 1, score: 0, voterCount: 0, item: publicItem(item) }));
  }
  return json(200, { segment, windowDays: 90, sampleSize: rows.length, items });
}

async function ingestCatalog(deps, body, auth) {
  if (auth?.via !== "admin") return json(403, { error: "admin required" });
  if (!deps.tables.entities || !deps.tables.edges) return json(503, { error: "catalog v2 not configured" });
  const records = Array.isArray(body.records) ? body.records.slice(0, 50) : [];
  if (!records.length) return json(400, { error: "records required" });
  let written = 0;
  for (const record of records) {
    const payload = record.payload ?? record;
    const entityId = stableEntityId({ ...payload, source: record.source, entityId: record.entityId });
    const item = normalizeLegacyPost({ ...payload, postId: entityId });
    item.sourceKey = sourceIdentity({ ...payload, source: record.source });
    await deps.ddb.send(new PutCommand({ TableName: deps.tables.entities, Item: item }));
    const edges = [];
    for (const assertion of item.taxonomy.assertions) {
      const labelId = `label:${assertion.labelId}`;
      await deps.ddb.send(new PutCommand({
        TableName: deps.tables.entities,
        Item: { entityId: labelId, entityType: "label", schemaVersion: 2, title: assertion.labelId, status: "active", updatedAt: Date.now() },
      }));
      edges.push({ fromId: item.entityId, edgeKey: `HAS_LABEL#${labelId}`, toId: labelId, reverseKey: `HAS_LABEL#${item.entityId}`, relation: "HAS_LABEL", evidence: assertion });
    }
    for (const offer of item.commerce.offers) {
      await deps.ddb.send(new PutCommand({ TableName: deps.tables.entities, Item: { entityId: offer.offerId, entityType: "offer", schemaVersion: 2, ...offer, status: "active", updatedAt: Date.now() } }));
      edges.push({ fromId: item.entityId, edgeKey: `AVAILABLE_AS#${offer.offerId}`, toId: offer.offerId, reverseKey: `AVAILABLE_AS#${item.entityId}`, relation: "AVAILABLE_AS" });
    }
    if (edges.length) await deps.ddb.send(new BatchWriteCommand({
      RequestItems: { [deps.tables.edges]: edges.map((Item) => ({ PutRequest: { Item } })) },
    }));
    written++;
  }
  return json(200, { ok: true, written });
}

export function createRecommenderV2(deps = defaultDeps) {
  return async function route(method, path, body = {}, _qs = {}, context = {}) {
    if (method === "GET" && path === "/v2/feed-taxonomy") return json(200, { version: TAXONOMY_VERSION, themes: FEED_TAXONOMY }, { "cache-control": "public, max-age=3600" });
    if (method === "GET" && /^\/v2\/items\/[^/]+$/.test(path)) return getItem(deps, path);
    if (method === "POST" && path === "/v2/recommendations") return recommend(deps, body, context.auth);
    if (method === "POST" && path === "/v2/events/batch") return recordEvents(deps, body, context.auth);
    if (method === "POST" && path === "/v2/recipient-leaderboard") return recipientLeaderboard(deps, body);
    if (method === "POST" && path === "/internal/v2/catalog/records/batch") return ingestCatalog(deps, body, context.auth);
    return null;
  };
}

export const recommenderV2Routes = createRecommenderV2();
