const LOW_QUALITY_HINT = /(?:^|[-_/])(thumb|thumbnail|social|banner|infographic|comparison|size[-_]?chart)(?:[-_/?.]|$)/i;

function jpegDimensions(bytes) {
  for (let offset = 2; offset + 9 < bytes.length;) {
    if (bytes[offset] !== 0xff) { offset += 1; continue; }
    const marker = bytes[offset + 1];
    const length = bytes.readUInt16BE(offset + 2);
    if ([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf].includes(marker)) {
      return { width: bytes.readUInt16BE(offset + 7), height: bytes.readUInt16BE(offset + 5) };
    }
    if (length < 2) break;
    offset += 2 + length;
  }
}

export function imageDimensions(bytes, contentType = "") {
  if (!Buffer.isBuffer(bytes) || bytes.length < 24) return undefined;
  if (bytes.subarray(1, 4).toString() === "PNG" || contentType.includes("png")) {
    return { width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20) };
  }
  if (bytes[0] === 0xff && bytes[1] === 0xd8) return jpegDimensions(bytes);
  if (bytes.subarray(0, 4).toString() === "RIFF" && bytes.subarray(8, 12).toString() === "WEBP") {
    const codec = bytes.subarray(12, 16).toString();
    if (codec === "VP8X" && bytes.length >= 30) {
      return {
        width: 1 + bytes.readUIntLE(24, 3),
        height: 1 + bytes.readUIntLE(27, 3),
      };
    }
    if (codec === "VP8 " && bytes.length >= 30) {
      return { width: bytes.readUInt16LE(26) & 0x3fff, height: bytes.readUInt16LE(28) & 0x3fff };
    }
    if (codec === "VP8L" && bytes.length >= 25) {
      const bits = bytes.readUInt32LE(21);
      return { width: (bits & 0x3fff) + 1, height: ((bits >> 14) & 0x3fff) + 1 };
    }
  }
}

export function evaluateMediaQuality({ url = "", width, height, detectedText = [] }) {
  const reasons = [];
  const megapixels = width && height ? width * height / 1_000_000 : 0;
  const aspectRatio = width && height ? width / height : 0;
  if (!width || !height) reasons.push("dimensions_unknown");
  if (width && height && (Math.min(width, height) < 800 || megapixels < 0.75)) reasons.push("low_resolution");
  if (aspectRatio && (aspectRatio < 0.6 || aspectRatio > 1.8)) reasons.push("extreme_aspect_ratio");
  if (LOW_QUALITY_HINT.test(url)) reasons.push("marketing_or_thumbnail_url");
  if (detectedText.length > 6) reasons.push("text_heavy");

  const blocking = reasons.some((reason) => ["low_resolution", "marketing_or_thumbnail_url", "text_heavy"].includes(reason));
  const primaryEligible = !blocking && !reasons.includes("dimensions_unknown") && !reasons.includes("extreme_aspect_ratio");
  const galleryEligible = !blocking && !reasons.includes("dimensions_unknown");
  const score = Math.max(0, 1 - reasons.reduce((sum, reason) => sum + ({
    low_resolution: 0.55,
    marketing_or_thumbnail_url: 0.4,
    text_heavy: 0.5,
    extreme_aspect_ratio: 0.25,
    dimensions_unknown: 0.3,
  }[reason] ?? 0), 0));

  return {
    width, height,
    megapixels: Number(megapixels.toFixed(2)),
    aspectRatio: Number(aspectRatio.toFixed(3)),
    detectedTextLines: detectedText.length,
    score: Number(score.toFixed(2)),
    status: primaryEligible ? "approved_primary" : galleryEligible ? "gallery_only" : "rejected",
    primaryEligible,
    galleryEligible,
    reasons,
  };
}
