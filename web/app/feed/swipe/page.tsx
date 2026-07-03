"use client";

import { Suspense, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { SwipeDeck } from "@/components/app/swipe-deck";
import { ShareSheet } from "@/components/app/share-sheet";
import { Icons } from "@/components/ui";
import { useCurrentUser } from "@/lib/identity";
import { getShareSenderId } from "@/lib/api";
import { buildInviteUrl } from "@/lib/invite";
import { useServerChallengePrepare } from "@/lib/use-server-challenge";
import { EVENT_TYPE_META, type EventType } from "@/lib/events";

export default function SwipePage() {
  return (
    <Suspense fallback={null}>
      <SwipeInner />
    </Suspense>
  );
}

function SwipeInner() {
  const params = useSearchParams();
  const me = useCurrentUser();
  const firstName = me.name !== "You" ? me.name.split(/\s+/)[0] : null;
  const [senderId, setSenderId] = useState<string | null>(null);
  const [to, setTo] = useState(() => params.get("to") ?? "");
  const [occasion, setOccasion] = useState<EventType>(() => {
    const q = params.get("occasion");
    return q && q in EVENT_TYPE_META ? (q as EventType) : "birthday";
  });
  const [date, setDate] = useState(() => params.get("date") ?? "");

  useEffect(() => {
    // Read the share sender id after mount (Clerk userId if signed in, else a
    // persistent anon id). SSR-safe; touches localStorage.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setSenderId(getShareSenderId());
  }, []);

  const inviterName = me.name !== "You" ? me.name : "A friend";
  const url = useMemo(
    () =>
      buildInviteUrl(inviterName, {
        ...(senderId ? { senderId } : {}),
        to,
        occasion,
        date,
      }),
    [inviterName, senderId, to, occasion, date]
  );
  // "Share the challenge" builds the deck server-side around this user's
  // recent yes-swipes (POST /challenges) — the link then carries the
  // challengeId. No swipes yet / API down → legacy local-deck link.
  const prepareServerChallenge = useServerChallengePrepare({
    senderId,
    inviterName,
    to,
    occasion,
    date,
  });

  const occasionLabel = EVENT_TYPE_META[occasion]?.label.toLowerCase() ?? "occasion";
  const text =
    "Would you want this gifted to you? 👀 Swipe to find your gift taste on Giftmaxxing";

  return (
    <div className="mx-auto max-w-2xl px-4 py-8">
      <div className="text-center">
        <span className="inline-flex items-center gap-1.5 rounded-full bg-coral-soft px-3 py-1 text-xs font-bold text-coral">
          <Icons.trend size={14} /> Viral challenge
        </span>
        <h1 className="mt-3 font-display text-3xl font-extrabold leading-tight text-ink">
          Would you want this gifted to you?
        </h1>
        <p className="mx-auto mt-2 max-w-md text-ink-soft">
          {firstName ? `${firstName}, swipe` : "Swipe"} right for yes, left for no. Every swipe
          trains your gift recommendations.
        </p>
        {/* Personalize (optional): the sender sets who it's for + the occasion,
            so the recipient never has to type a name or pick a birthday. */}
        <div className="mx-auto mt-5 max-w-md rounded-2xl border border-line bg-surface p-4 text-left">
          <p className="mb-3 text-xs font-bold uppercase tracking-widest text-ink-faint">
            Personalize (optional)
          </p>
          <div className="grid gap-3 sm:grid-cols-2">
            <label className="block">
              <span className="mb-1 block text-xs font-semibold text-ink-soft">Their name</span>
              <input
                type="text"
                value={to}
                onChange={(e) => setTo(e.target.value)}
                placeholder="e.g. Maya"
                className="w-full rounded-xl border border-line bg-cream px-3 py-2 text-sm font-medium text-ink outline-none focus:border-coral focus:ring-2 focus:ring-coral/20"
              />
            </label>
            <label className="block">
              <span className="mb-1 block text-xs font-semibold text-ink-soft">Occasion</span>
              <select
                value={occasion}
                onChange={(e) => setOccasion(e.target.value as EventType)}
                className="w-full rounded-xl border border-line bg-cream px-3 py-2 text-sm font-medium text-ink outline-none focus:border-coral focus:ring-2 focus:ring-coral/20"
              >
                {(Object.keys(EVENT_TYPE_META) as EventType[]).map((k) => (
                  <option key={k} value={k}>
                    {EVENT_TYPE_META[k].emoji} {EVENT_TYPE_META[k].label}
                  </option>
                ))}
              </select>
            </label>
            <label className="block sm:col-span-2">
              <span className="mb-1 block text-xs font-semibold text-ink-soft">
                Date <span className="font-normal text-ink-faint">(so you never forget it)</span>
              </span>
              <input
                type="date"
                value={date}
                onChange={(e) => setDate(e.target.value)}
                className="w-full rounded-xl border border-line bg-cream px-3 py-2 text-sm font-medium text-ink outline-none focus:border-coral focus:ring-2 focus:ring-coral/20"
              />
            </label>
          </div>
        </div>

        <div className="mt-4 flex justify-center">
          <ShareSheet
            url={url}
            prepare={prepareServerChallenge}
            text={text}
            subject={`${inviterName} wants to find you the perfect gift`}
            recipientName={to.trim() || "someone"}
            note={
              senderId ? (
                <>
                  When {to.trim() || "someone"} finishes your challenge, we save a{" "}
                  <strong className="font-semibold text-ink-soft">soft profile</strong> — their gift
                  taste{date ? ` plus the ${occasionLabel} you set` : ""} — to{" "}
                  <strong className="font-semibold text-ink-soft">your</strong> account so you can
                  gift them. By sharing, you confirm they&apos;re okay with it and take
                  responsibility.{" "}
                  <Link href="/privacy#sender" className="underline hover:text-ink">
                    Sender privacy
                  </Link>
                  .
                </>
              ) : (
                <>
                  Sign in first so we can tell you when they finish and save their gift taste to
                  your account.{" "}
                  <Link href="/privacy#sender" className="underline hover:text-ink">
                    Sender privacy
                  </Link>
                  .
                </>
              )
            }
          />
        </div>
      </div>

      <div className="mt-8">
        <SwipeDeck />
      </div>

      <p className="mx-auto mt-8 max-w-md text-center text-xs leading-relaxed text-ink-faint">
        Your &ldquo;yes&rdquo; swipes become the taste centroid for our S3 Vectors recommender —
        the more you swipe, the sharper your matches get.
      </p>
    </div>
  );
}
