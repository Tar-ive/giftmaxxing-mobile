import { assemble } from "../lib/ffmpeg.mjs";
export const run = (brief, dirs) => assemble(brief, dirs);
