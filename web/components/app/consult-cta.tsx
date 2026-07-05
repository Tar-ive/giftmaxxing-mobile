"use client";

// One-line invitation from the feed into the /gift consult. Dismissible per
// browser (localStorage) so it never becomes wallpaper.

import { useEffect, useState } from "react";
import Link from "next/link";
import { Maxi } from "@/components/ui";

const DISMISS_KEY = "gm_consult_cta_dismissed";

export function ConsultCta() {
  const [hidden, setHidden] = useState(true);

  useEffect(() => {
    try {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- hydrate persisted state on mount
      setHidden(localStorage.getItem(DISMISS_KEY) === "1");
    } catch {
      setHidden(false);
    }
  }, []);

  if (hidden) return null;

  const dismiss = () => {
    setHidden(true);
    try {
      localStorage.setItem(DISMISS_KEY, "1");
    } catch {
      /* fine — session-only dismissal */
    }
  };

  return (
    <div className="flex items-center gap-3 rounded-2xl border border-coral/25 bg-coral-soft/40 px-4 py-3">
      <Maxi size={34} />
      <Link href="/gift" className="min-w-0 flex-1">
        <p className="text-sm font-bold text-ink">Stuck on someone?</p>
        <p className="truncate text-xs text-ink-soft">
          60-second consult — I&apos;ll find a gift they&apos;d pack when they move →
        </p>
      </Link>
      <button
        onClick={dismiss}
        aria-label="Dismiss"
        className="shrink-0 rounded-full p-1.5 text-ink-faint transition-colors hover:bg-ink/5 hover:text-ink"
      >
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
          <path d="M6 6l12 12M18 6 6 18" />
        </svg>
      </button>
    </div>
  );
}
