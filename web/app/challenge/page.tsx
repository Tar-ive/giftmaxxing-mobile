"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { ShareSheet } from "@/components/app/share-sheet";
import { Icons, Maxi } from "@/components/ui";
import { buildInviteUrl } from "@/lib/invite";
import { getShareSenderId, getMyUserId } from "@/lib/api";
import { useServerChallengePrepare } from "@/lib/use-server-challenge";
import { EVENT_TYPE_META, type EventType } from "@/lib/events";

const clerkEnabled = !!process.env.NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY;

// Public "share a gift challenge" page — works fully signed-out.
//
// Anyone (no account) can personalize + share a swipe challenge. We attribute it
// to getShareSenderId() — the Clerk userId if signed in, otherwise a persistent
// anon id (lib/anon.ts). Every response lands server-side under that id; signing
// in claims them onto the real account (AccountSync). Seeing results needs auth.
export default function ChallengePage() {
  const [yourName, setYourName] = useState("");
  const [to, setTo] = useState("");
  const [occasion, setOccasion] = useState<EventType>("birthday");
  const [date, setDate] = useState("");
  const [senderId, setSenderId] = useState("");
  const [signedIn, setSignedIn] = useState(false);

  useEffect(() => {
    // Read/mint the share sender id after mount (SSR-safe; touches localStorage).
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setSenderId(getShareSenderId());
    setSignedIn(!!getMyUserId());
  }, []);

  const inviterName = yourName.trim() || "A friend";
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

  // Tapping "Share the challenge" upgrades the link to a server-built deck
  // (POST /challenges seeded with this browser's recent yes-swipes); falls
  // back to the legacy local-deck link when there's no seed / no API.
  const prepareServerChallenge = useServerChallengePrepare({
    senderId: senderId || null,
    inviterName,
    to,
    occasion,
    date,
  });

  const occasionLabel = EVENT_TYPE_META[occasion]?.label.toLowerCase() ?? "occasion";
  const them = to.trim() || "them";
  const text =
    "Would you want this gifted to you? 👀 Swipe to find your gift taste on Giftmaxxing";
  const signInHref = "/sign-in?redirect_url=/feed/activity";

  return (
    <main className="min-h-screen bg-cream text-ink">
      {/* Top bar */}
      <header className="mx-auto flex max-w-3xl items-center justify-between px-5 py-5">
        <Link href="/" className="font-display text-lg font-extrabold text-ink">
          Giftmaxxing
        </Link>
        {signedIn ? (
          <Link
            href="/feed/activity"
            className="text-sm font-bold text-coral hover:opacity-80"
          >
            Your responses →
          </Link>
        ) : clerkEnabled ? (
          <Link href={signInHref} className="text-sm font-bold text-coral hover:opacity-80">
            Sign in
          </Link>
        ) : null}
      </header>

      <section className="mx-auto max-w-xl px-5 pb-20 pt-6 text-center">
        <span className="inline-flex items-center gap-1.5 rounded-full bg-coral-soft px-3 py-1 text-xs font-bold text-coral">
          <Icons.trend size={14} /> Viral gift challenge
        </span>

        <h1 className="mt-4 font-display text-4xl font-extrabold leading-[1.05] tracking-tight text-ink sm:text-5xl">
          Find their exact gift taste — without asking
        </h1>

        <p className="mx-auto mt-4 max-w-md text-lg leading-relaxed text-ink-soft">
          Share a 60-second swipe challenge. {to.trim() ? `${them.split(/\s+/)[0]}` : "They"} swipe
          through gift ideas, <span className="font-semibold text-ink">Maxi</span> learns what they
          love, and you get a ready-made gift list. <span className="font-semibold text-ink">No
          sign-up needed to share.</span>
        </p>

        {/* Personalize */}
        <div className="mx-auto mt-8 max-w-md rounded-2xl border border-line bg-surface p-5 text-left shadow-sm">
          <p className="mb-3 text-xs font-bold uppercase tracking-widest text-ink-faint">
            Personalize your challenge
          </p>
          <div className="grid gap-3 sm:grid-cols-2">
            <label className="block sm:col-span-2">
              <span className="mb-1 block text-xs font-semibold text-ink-soft">Your name</span>
              <input
                type="text"
                value={yourName}
                onChange={(e) => setYourName(e.target.value)}
                placeholder="e.g. Alex"
                className="w-full rounded-xl border border-line bg-cream px-3 py-2 text-sm font-medium text-ink outline-none focus:border-coral focus:ring-2 focus:ring-coral/20"
              />
            </label>
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

          <div className="mt-5 flex justify-center">
            <ShareSheet
              url={url}
              prepare={prepareServerChallenge}
              text={text}
              subject={`${inviterName} wants to find you the perfect gift`}
              recipientName={to.trim() || "someone"}
              triggerLabel="Share the challenge"
              triggerClassName="inline-flex items-center gap-2 rounded-full bg-coral px-7 py-3.5 text-base font-bold text-white shadow-lg shadow-coral/30 transition-transform hover:-translate-y-0.5"
              note={
                <>
                  When {them} finishes, we save their gift taste
                  {date ? ` plus the ${occasionLabel} you set` : ""} so you can gift them.{" "}
                  <Link href="/privacy#sender" className="underline hover:text-ink">
                    Sender privacy
                  </Link>
                  .
                </>
              }
            />
          </div>
        </div>

        {/* Results gate */}
        <div className="mx-auto mt-6 max-w-md rounded-2xl border border-line bg-surface p-5 text-left">
          <div className="flex items-start gap-3">
            <Maxi size={36} />
            {signedIn ? (
              <div>
                <p className="text-sm font-bold text-ink">You&apos;re all set.</p>
                <p className="mt-1 text-sm text-ink-soft">
                  Every response shows up in{" "}
                  <Link href="/feed/activity" className="font-semibold text-coral hover:opacity-80">
                    your activity
                  </Link>{" "}
                  with their gift taste, ready for you to shop.
                </p>
              </div>
            ) : (
              <div>
                <p className="text-sm font-bold text-ink">Want to see who responds?</p>
                <p className="mt-1 text-sm text-ink-soft">
                  Share it now — no account needed. We remember your challenge on this device, and
                  the moment you{" "}
                  {clerkEnabled ? (
                    <Link href={signInHref} className="font-semibold text-coral hover:opacity-80">
                      sign in
                    </Link>
                  ) : (
                    <span className="font-semibold text-ink">sign in</span>
                  )}{" "}
                  every response is saved to your account so you can track and shop them.
                </p>
              </div>
            )}
          </div>
        </div>

        <p className="mx-auto mt-6 max-w-md text-xs leading-relaxed text-ink-faint">
          Each swipe trains Giftmaxxing&apos;s recommender, so the gift list gets sharper the more
          they swipe.
        </p>
      </section>
    </main>
  );
}
