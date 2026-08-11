import { GetObjectCommand, S3Client } from "@aws-sdk/client-s3";

const bucket = process.env.RECOMMENDER_MODEL_BUCKET;
const key = process.env.RECOMMENDER_MODEL_KEY || "models/active.json";
const s3 = bucket ? new S3Client({}) : null;
let cached = null;
let cachedAt = 0;

const sigmoid = (value) => 1 / (1 + Math.exp(-Math.max(-30, Math.min(30, value))));

export async function activeRecommenderModel(deps = {}) {
  if (!bucket || !s3) return null;
  if (cachedAt > Date.now() - 60_000) return cached;
  try {
    const result = await (deps.s3 ?? s3).send(new GetObjectCommand({ Bucket: bucket, Key: key }));
    cached = JSON.parse(await result.Body.transformToString());
  } catch (error) {
    if (!["NoSuchKey", "AccessDenied"].includes(error.name)) console.warn("active recommender model unavailable", error.message);
    cached = null;
  }
  cachedAt = Date.now();
  return cached;
}

export function modelProbability(active, candidate, profile = {}) {
  const model = active?.model;
  if (!model?.w || model.w.length !== 10 || !model.mu || !model.sd) return null;
  const item = candidate.item;
  const offer = item.commerce?.offers?.[0] ?? {};
  const price = Number(offer.price) || 0;
  const preferred = Number(profile.preferredPrice) || 0;
  const category = item.taxonomy?.primaryCategoryId;
  const retailer = item.provenance?.type === "retailer";
  const features = [
    Number(candidate.taste ?? 0.5), 0, Math.log1p(price),
    preferred > 0 && price > 0 ? Math.exp(-Math.abs(Math.log(price / preferred))) : 0.5,
    Number(profile.labelWeights?.[category] > 0), 0,
    Math.log1p(Number(item.legacyPost?.likes) || 0),
    Number((item.media?.length ?? 0) > 1), Number(Boolean(item.summary)), Number(retailer),
  ];
  const score = features.reduce((sum, value, index) => sum + ((value - model.mu[index]) / Math.max(model.sd[index], 1e-6)) * model.w[index], Number(model.b) || 0);
  return sigmoid(score);
}
