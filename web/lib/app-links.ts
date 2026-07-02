// ────────────────────────────────────────────────────────────────────────────
// Native-app download links — the Instagram-style conversion surface.
//
// The guest swipe flow runs fully in the mobile browser (zero friction for the
// viral loop); these helpers power the "get the app" prompts that convert a
// finished guest into an install or an account. Everything is driven by env so
// the CTAs stay hidden until a real App Store listing exists:
//
//   NEXT_PUBLIC_APP_STORE_URL  e.g. https://apps.apple.com/app/id6740000000
//                              (or a TestFlight link during beta)
//   NEXT_PUBLIC_APPLE_APP_ID   numeric App Store id; enables Safari's native
//                              Smart App Banner (apple-itunes-app meta).
// ────────────────────────────────────────────────────────────────────────────

export const APP_STORE_URL = process.env.NEXT_PUBLIC_APP_STORE_URL ?? "";
export const APPLE_APP_ID = process.env.NEXT_PUBLIC_APPLE_APP_ID ?? "";

/** True when an installable app exists to point people at. */
export function appDownloadAvailable(): boolean {
  return APP_STORE_URL.length > 0;
}

/** iOS-ish user agent — the only platform we have an app for today. */
export function isIOSBrowser(): boolean {
  if (typeof navigator === "undefined") return false;
  return /iPhone|iPad|iPod/i.test(navigator.userAgent);
}
