"use client";

import { APP_STORE_URL, appDownloadAvailable } from "@/lib/app-links";

// The post-challenge conversion block — shown on the invite REVEAL, the
// highest-intent moment of the guest flow (they just saw their personalized
// gift set). Instagram-style priority: the native app is the primary ask;
// managing on the web (sign-in) is the secondary path rendered right below by
// GuestClaimCard. Hidden entirely until an App Store link is configured.
export function AppDownloadCTA() {
  if (!appDownloadAvailable()) return null;

  return (
    <div className="mt-8 rounded-3xl border border-ink/10 bg-ink p-6 text-center">
      <h3 className="font-display text-xl font-extrabold text-cream">
        Keep your gift taste with you
      </h3>
      <p className="mx-auto mt-1.5 max-w-sm text-sm text-cream/70">
        Get the Giftmaxxing app to manage your picks, swipe new drops daily, and
        gift your people back.
      </p>
      <a
        href={APP_STORE_URL}
        target="_blank"
        rel="noopener noreferrer"
        className="mt-5 inline-flex items-center gap-2 rounded-full bg-cream px-7 py-3 text-sm font-bold text-ink transition-opacity hover:opacity-90"
      >
         Download on the App Store
      </a>
      <p className="mt-3 text-[11px] text-cream/50">
        Free — takes 30 seconds. Or manage everything on the web below.
      </p>
    </div>
  );
}
