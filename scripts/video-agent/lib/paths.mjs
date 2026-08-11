import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

// scripts/video-agent/lib/paths.mjs -> repo root is four levels up.
export const ROOT = dirname(dirname(dirname(dirname(fileURLToPath(import.meta.url)))));
export const path = (...segments) => join(ROOT, ...segments);
export const sharpModule = () => import(join(ROOT, "web/node_modules/sharp/lib/index.js"));
