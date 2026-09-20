// ────────────────────────────────────────────────────────────────────────────
// Native-app download links — the Instagram-style conversion surface.
//
// The guest swipe flow runs fully in the mobile browser (zero friction for the
// viral loop); these helpers power the "get the app" prompts that convert a
// finished guest into an install or an account. The listing is live, so these
// default to it; env still overrides, for a TestFlight link on a beta deploy:
//
//   NEXT_PUBLIC_APP_STORE_URL  a full listing or TestFlight URL
//   NEXT_PUBLIC_APPLE_APP_ID   numeric App Store id; drives Safari's native
//                              Smart App Banner (apple-itunes-app meta).
// ────────────────────────────────────────────────────────────────────────────

/** The live App Store listing. */
export const APP_STORE_LISTING_URL =
  "https://apps.apple.com/us/app/giftmaxxing/id6788124639";

export const APP_STORE_URL =
  process.env.NEXT_PUBLIC_APP_STORE_URL || APP_STORE_LISTING_URL;
export const APPLE_APP_ID = process.env.NEXT_PUBLIC_APPLE_APP_ID || "6788124639";

/** True when an installable app exists to point people at. */
export function appDownloadAvailable(): boolean {
  return APP_STORE_URL.length > 0;
}

/** iOS-ish user agent — the only platform we have an app for today. */
export function isIOSBrowser(): boolean {
  if (typeof navigator === "undefined") return false;
  return /iPhone|iPad|iPod/i.test(navigator.userAgent);
}
