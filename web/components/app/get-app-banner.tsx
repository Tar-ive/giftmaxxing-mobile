"use client";

import { useEffect, useState } from "react";
import { Maxi } from "@/components/ui";
import { APP_STORE_URL, appDownloadAvailable } from "@/lib/app-links";

// Slim, dismissible "better in the app" banner pinned to the top of the guest
// invite flow — the Instagram pattern: visible from the very first screen, but
// never blocking the shared task (the swipe challenge stays fully usable in
// the browser). Dismissal is remembered for the session only, so a returning
// guest sees it again. Renders nothing until an App Store link is configured.
const DISMISS_KEY = "giftmaxxing_app_banner_dismissed";

export function GetAppBanner() {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    if (!appDownloadAvailable()) return;
    try {
      setVisible(sessionStorage.getItem(DISMISS_KEY) !== "1");
    } catch {
      setVisible(true);
    }
  }, []);

  const dismiss = () => {
    setVisible(false);
    try {
      sessionStorage.setItem(DISMISS_KEY, "1");
    } catch {
      // storage disabled — banner just stays dismissed for this render
    }
  };

  if (!visible) return null;

  return (
    <div className="sticky top-0 z-40 flex items-center gap-3 border-b border-line bg-surface/95 px-4 py-2.5 backdrop-blur">
      <Maxi size={28} />
      <div className="min-w-0 flex-1">
        <p className="truncate text-xs font-bold text-ink">Giftmaxxing is better in the app</p>
        <p className="truncate text-[11px] text-ink-faint">Swipe, save and never miss a gift moment</p>
      </div>
      <a
        href={APP_STORE_URL}
        target="_blank"
        rel="noopener noreferrer"
        className="rounded-full bg-coral px-4 py-1.5 text-xs font-bold text-white transition-opacity hover:opacity-90"
      >
        Get
      </a>
      <button
        onClick={dismiss}
        aria-label="Dismiss app banner"
        className="px-1 text-lg leading-none text-ink-faint transition-colors hover:text-ink"
      >
        ×
      </button>
    </div>
  );
}
