"use client";

// /gift — the Gift Concierge.
//
// The product thesis, as a page: a friend who's good at gifts doesn't show you
// an infinite feed — they ask a few sharp questions about the PERSON, then say
// "get them this." This is that consult as a conversation, ending in a short
// list where every item passes the move test ("if they moved tomorrow, does it
// make it into the box?"). Public route: no account needed, built to be the
// link you send when someone texts "help, what do I get my mom".
//
// The consult itself lives in components/app/gift-consult.tsx — the SAME
// component is the onboarding flow (/onboarding), because meeting the
// concierge IS the product tour.

import Link from "next/link";
import { GiftConsult } from "@/components/app/gift-consult";
import { Maxi } from "@/components/ui";

export default function GiftConciergePage() {
  return (
    <div className="mx-auto flex min-h-dvh max-w-2xl flex-col px-4 pb-6 pt-4 sm:px-6">
      {/* Header */}
      <header className="mb-2 flex items-center justify-between">
        <Link href="/" className="flex items-center gap-2.5">
          <Maxi size={34} />
          <div>
            <p className="font-display text-lg font-extrabold leading-none text-ink">Gift Concierge</p>
            <p className="text-[11px] font-medium text-ink-faint">gifts that survive the next move</p>
          </div>
        </Link>
        <Link
          href="/feed"
          className="rounded-full border border-line bg-surface px-4 py-2 text-xs font-bold text-ink transition-colors hover:border-ink/25"
        >
          Open the app
        </Link>
      </header>

      <GiftConsult />
    </div>
  );
}
