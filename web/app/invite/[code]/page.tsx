"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import Link from "next/link";
import { Maxi, Icons } from "@/components/ui";
import { SwipeDeck } from "@/components/app/swipe-deck";
import { decodeInvite, saveInviteSession, clearInviteSession } from "@/lib/invite";
import {
  createConnection,
  fetchChallenge,
  submitChallengeResponse,
  type ChallengeDeckItem,
  type ChallengeSwipe,
} from "@/lib/api";
import { swipeVibes, seedKeysFromSwipes, loadSwipes, localMatchesFromSwipes, swipeTimingSignals, type SwipeDir } from "@/lib/swipes";
import { GRADIENTS, type Grad } from "@/lib/data";
import { shortTitle } from "@/lib/feed-builder";
import { type Pin } from "@/lib/pins";
import { GuestClaimCard } from "@/components/app/guest-claim-card";
import { GetAppBanner } from "@/components/app/get-app-banner";
import { AppDownloadCTA } from "@/components/app/app-download-cta";
import { PoolInvite } from "@/components/app/pool-invite";
import { EVENT_TYPE_META, type EventType, parseISODate } from "@/lib/events";
import { saveLocalConnection } from "@/lib/local-connections";
import { saveSoftProfile } from "@/lib/soft-profile";
import { type GenderPref, GENDER_PREF_META } from "@/lib/gender-prefs";

const clerkEnabled = !!process.env.NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY;

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

// Format a sender-set event date ("YYYY-MM-DD") as e.g. "Jun 30" for the invite.
function formatInviteDate(iso?: string): string | null {
  if (!iso) return null;
  const p = parseISODate(iso);
  return p ? `${MONTHS[p.m - 1]} ${p.d}` : null;
}

// Server challenge deck item → the Pin shape SwipeDeck renders. Gradient is a
// stable hash of the id so cards look consistent across re-renders.
const GRAD_KEYS = Object.keys(GRADIENTS) as Grad[];
function deckItemToPin(it: ChallengeDeckItem): Pin {
  let h = 0;
  for (let i = 0; i < it.postId.length; i++) h = (h * 31 + it.postId.charCodeAt(i)) >>> 0;
  return {
    id: it.postId,
    title: it.name || "Gift find",
    image: it.image || "",
    thumb: it.image || "",
    source: it.domain || "",
    brand: (it.domain || "").replace(/^www\./, "") || "Gift find",
    url: it.url || "",
    price: it.price ?? 0,
    grad: GRAD_KEYS[h % GRAD_KEYS.length] ?? "peach",
    emoji: "\u{1F381}",
    category: it.category || "gift",
  };
}

// ── Phases ──────────────────────────────────────────────────────────────────
type Phase = "welcome" | "consent" | "preference" | "swipe" | "birthday" | "reveal";

export default function InvitePage() {
  const params = useParams<{ code: string }>();
  const router = useRouter();
  const code = params.code;

  const invite = useMemo(() => decodeInvite(code), [code]);
  const inviterName = invite?.name ?? "Someone";

  // The sender can carry the occasion + date in the link, so the invite feels
  // personal ("for your birthday") and shows they know the date.
  const occasionMeta =
    invite?.occasion && invite.occasion in EVENT_TYPE_META
      ? EVENT_TYPE_META[invite.occasion as EventType]
      : null;
  const occasionLabel = occasionMeta?.label.toLowerCase();
  const eventDateStr = formatInviteDate(invite?.date);

  const [phase, setPhase] = useState<Phase>("welcome");
  const [results, setResults] = useState<Pin[]>([]);
  const [birthday, setBirthday] = useState(invite?.date ?? "");
  const [genderPref, setGenderPref] = useState<GenderPref | null>(null);
  const [transitioning, setTransitioning] = useState(false);
  const reportedRef = useRef(false);

  // Server-side challenge: fetch the pre-built seeded deck up front (while the
  // guest reads the welcome/consent screens). "failed" falls back to the
  // legacy local deck so an expired challenge still gives a good experience.
  const challengeId = invite?.challengeId;
  const [serverDeck, setServerDeck] = useState<Pin[] | null>(null);
  const [deckState, setDeckState] = useState<"idle" | "loading" | "ready" | "failed">(
    challengeId ? "loading" : "idle"
  );
  const challengeSwipesRef = useRef<ChallengeSwipe[]>([]);

  useEffect(() => {
    if (!challengeId) return;
    let cancelled = false;
    void fetchChallenge(challengeId).then((challenge) => {
      if (cancelled) return;
      if (challenge?.deck?.length) {
        setServerDeck(challenge.deck.map(deckItemToPin));
        setDeckState("ready");
      } else {
        setDeckState("failed");
      }
    });
    return () => {
      cancelled = true;
    };
  }, [challengeId]);

  const onChallengeSwipe = useCallback((id: string, dir: SwipeDir, dwellMs: number) => {
    challengeSwipesRef.current.push({ id, dir, dwellMs });
  }, []);

  // The sender can pre-set who the gift set is for, so the guest never types a
  // name or picks a birthday. Used only for a friendly greeting on the reveal.
  const guestName = invite?.to?.trim() || "Friend";
  const guestFirst = guestName.split(/\s+/)[0];

  const transition = useCallback((next: Phase) => {
    setTransitioning(true);
    setTimeout(() => {
      setPhase(next);
      setTransitioning(false);
    }, 300);
  }, []);

  const goToConsent = useCallback(() => {
    transition("consent");
  }, [transition]);

  const goToPreference = useCallback(() => {
    transition("preference");
  }, [transition]);

  const startSwiping = useCallback(() => {
    saveInviteSession({ inviterName, code, startedAt: Date.now() });
    transition("swipe");
  }, [inviterName, code, transition]);

  const reportConnection = useCallback(() => {
    if (reportedRef.current) return;
    reportedRef.current = true;
    const swipes = loadSwipes();
    const name = invite?.to?.trim() || "Friend";
    const guestBirthday = birthday || invite?.date || undefined;
    const vibes = swipeVibes(5);
    const seeds = seedKeysFromSwipes(8);

    // Server-challenge path: post the deck swipes back — the Lambda computes
    // the verdict against the hidden seed AND mirrors a soft-profile
    // connection, so createConnection would double-report. Deduped to the
    // guest's final answer per card (undo/redo keeps only the last).
    const challengeSwipes = [
      ...new Map(challengeSwipesRef.current.map((s) => [s.id, s])).values(),
    ];
    if (invite?.challengeId && challengeSwipes.length) {
      const fallbackSenderId = invite?.senderId;
      void submitChallengeResponse(
        invite.challengeId,
        { name, birthday: guestBirthday, genderPref: genderPref ?? undefined },
        challengeSwipes
      ).then((ok) => {
        if (!ok && fallbackSenderId) {
          // Challenge gone (expired/deleted) — report the classic way instead.
          void createConnection(fallbackSenderId, {
            name,
            birthday: guestBirthday,
            vibes,
            seeds,
            genderPref: genderPref ?? undefined,
            yesCount: swipes.filter((s) => s.dir === "yes").length,
            totalSwipes: swipes.length,
            dwellSignals: swipeTimingSignals(swipes),
          });
        }
      });
    } else if (invite?.senderId) {
      void createConnection(invite.senderId, {
        name,
        birthday: guestBirthday,
        vibes,
        seeds,
        genderPref: genderPref ?? undefined,
        yesCount: swipes.filter((s) => s.dir === "yes").length,
        totalSwipes: swipes.length,
        dwellSignals: swipeTimingSignals(swipes),
      });
    }

    const connId = `local_${Date.now().toString(36)}`;
    saveLocalConnection({
      userId: invite?.senderId ?? "unknown",
      connectionId: connId,
      soft: true,
      kind: "invite",
      guestName: name,
      birthday: guestBirthday,
      vibes,
      seeds,
      genderPref: genderPref ?? undefined,
      yesCount: swipes.filter((s) => s.dir === "yes").length,
      totalSwipes: swipes.length,
      seen: false,
      createdAt: Date.now(),
    });

    saveSoftProfile({
      name,
      vibes,
      seeds,
      birthday: guestBirthday,
      genderPref: genderPref ?? undefined,
      inviterName,
      completedAt: Date.now(),
    });

    clearInviteSession();
  }, [invite, birthday, inviterName, genderPref]);

  const onSwipeDone = useCallback(() => {
    // Server-deck flow: the reveal shows what the guest actually said yes to;
    // legacy flow keeps the local taste-match ranking.
    const yesIds = new Set(
      [...new Map(challengeSwipesRef.current.map((s) => [s.id, s])).values()]
        .filter((s) => s.dir === "yes")
        .map((s) => s.id)
    );
    const serverYes = (serverDeck ?? []).filter((p) => yesIds.has(p.id));
    setResults(serverYes.length ? serverYes.slice(0, 9) : localMatchesFromSwipes(9));
    // If the sender pre-set a date, skip the birthday step.
    if (invite?.date) {
      reportConnection();
      transition("reveal");
    } else {
      transition("birthday");
    }
  }, [invite, transition, reportConnection, serverDeck]);

  const finishChallenge = useCallback(() => {
    reportConnection();
    transition("reveal");
  }, [reportConnection, transition]);

  // ── Invalid invite code ─────────────────────────────────────────────────
  if (!invite) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center bg-cream px-4">
        <Maxi size={64} />
        <h1 className="mt-6 font-display text-2xl font-extrabold text-ink">
          Hmm, that link doesn&apos;t look right
        </h1>
        <p className="mt-2 text-sm text-ink-soft">
          Ask your friend to send a new invite link.
        </p>
        <button
          onClick={() => router.push("/")}
          className="mt-6 rounded-full bg-ink px-6 py-3 text-sm font-bold text-cream transition-opacity hover:opacity-90"
        >
          Go to Giftmaxxing
        </button>
      </div>
    );
  }

  // ── Group-gift invite — show the pool, require sign-in + consent to chip in ─
  if (invite.pool) {
    return <PoolInvite invite={invite} />;
  }

  // ── Transition wrapper ─────────────────────────────────────────────────────
  const transitionClass = transitioning
    ? "opacity-0 translate-y-4 transition-all duration-300"
    : "opacity-100 translate-y-0 transition-all duration-300";

  // ── Welcome phase ─────────────────────────────────────────────────────────
  if (phase === "welcome") {
    return (
      <div className={`flex min-h-screen flex-col bg-cream ${transitionClass}`}>
        <GetAppBanner />
        <div className="flex flex-1 flex-col items-center justify-center px-4">
        <Maxi size={72} />
        <h1 className="mt-6 text-center font-display text-3xl font-extrabold leading-tight text-ink sm:text-4xl">
          {inviterName} wants to find<br />your perfect gift
        </h1>
        {occasionMeta && (
          <span className="mt-4 inline-flex items-center gap-2 rounded-full bg-coral-soft px-3.5 py-1.5 text-sm font-bold text-coral">
            <span>{occasionMeta.emoji}</span>
            <span>
              {occasionMeta.label}
              {eventDateStr ? ` · ${eventDateStr}` : ""}
            </span>
          </span>
        )}
        <p className="mx-auto mt-3 max-w-md text-center text-ink-soft">
          {occasionLabel
            ? `${inviterName} wants to give you something special for your ${occasionLabel}. Swipe a few ideas so they know exactly what you'd love.`
            : `Swipe on gift ideas so ${inviterName} knows exactly what you'd love. No sign-up, no forms, just swipe!`}
        </p>
        <button
          onClick={goToConsent}
          className="mt-8 inline-flex items-center gap-2 rounded-full bg-coral px-8 py-3.5 text-base font-bold text-white shadow-lg shadow-coral/30 transition-opacity hover:opacity-90"
        >
          <Icons.heartFill size={20} /> Start swiping
        </button>
        <p className="mt-4 text-xs text-ink-faint">Takes less than a minute</p>
        <p className="mx-auto mt-3 max-w-xs text-center text-[11px] leading-relaxed text-ink-faint">
          {`Swiping shares your gift taste with ${inviterName} so they can gift you. No account or personal details needed. `}
          <a href="/privacy#recipient" className="underline hover:text-ink">
            How we use this
          </a>
          .
        </p>
        </div>
      </div>
    );
  }

  // ── Consent phase ─────────────────────────────────────────────────────────
  if (phase === "consent") {
    return (
      <div className={`flex min-h-screen flex-col items-center justify-center bg-cream px-4 ${transitionClass}`}>
        <div className="mx-auto max-w-md rounded-3xl border border-line bg-surface p-6 text-center shadow-lg">
          <span className="inline-flex h-14 w-14 items-center justify-center rounded-full bg-coral-soft text-2xl">🔒</span>
          <h2 className="mt-4 font-display text-xl font-extrabold text-ink">
            Before you swipe
          </h2>
          <p className="mt-2 text-sm text-ink-soft">
            Your swipes help {inviterName} pick gifts you&apos;d love. Here&apos;s what happens:
          </p>
          <ul className="mt-4 space-y-2 text-left text-sm text-ink-soft">
            <li className="flex items-start gap-2">
              <span className="mt-0.5 text-coral">♥</span>
              <span>Your <strong className="font-semibold text-ink">yes/no swipes</strong> are shared with {inviterName}</span>
            </li>
            <li className="flex items-start gap-2">
              <span className="mt-0.5 text-coral">🎁</span>
              <span><strong className="font-semibold text-ink">No account needed</strong> — swipe and you&apos;re done</span>
            </li>
            <li className="flex items-start gap-2">
              <span className="mt-0.5 text-coral">🔒</span>
              <span>We <strong className="font-semibold text-ink">never sell your data</strong> or share with third parties</span>
            </li>
          </ul>
          <button
            onClick={goToPreference}
            className="mt-6 w-full rounded-full bg-coral px-6 py-3 text-sm font-bold text-white shadow-lg shadow-coral/30 transition-opacity hover:opacity-90"
          >
            I&apos;m in — let&apos;s swipe
          </button>
          <p className="mt-3 text-[11px] text-ink-faint">
            By continuing, you agree to our{" "}
            <a href="/privacy#recipient" className="underline hover:text-ink">
              Privacy&nbsp;Policy
            </a>
            .
          </p>
        </div>
      </div>
    );
  }

  // ── Preference phase — gender/style toggle ─────────────────────────────────
  if (phase === "preference") {
    return (
      <div className={`flex min-h-screen flex-col items-center justify-center bg-cream px-4 ${transitionClass}`}>
        <div className="mx-auto max-w-md rounded-3xl border border-line bg-surface p-6 text-center shadow-lg">
          <span className="inline-flex h-14 w-14 items-center justify-center rounded-full bg-coral-soft text-2xl">✨</span>
          <h2 className="mt-4 font-display text-xl font-extrabold text-ink">
            What should we show you?
          </h2>
          <p className="mt-2 text-sm text-ink-soft">
            Pick your vibe so we can show you more relevant gift ideas.
          </p>
          <div className="mt-5 space-y-2">
            {(Object.keys(GENDER_PREF_META) as GenderPref[]).map((key) => {
              const meta = GENDER_PREF_META[key];
              const selected = genderPref === key;
              return (
                <button
                  key={key}
                  onClick={() => setGenderPref(key)}
                  aria-pressed={selected}
                  className={`flex w-full items-center gap-3 rounded-2xl border px-4 py-3 text-left transition-colors ${
                    selected
                      ? "border-coral bg-coral-soft"
                      : "border-line bg-cream hover:bg-coral-soft/40"
                  }`}
                >
                  <span className="text-2xl">{meta.emoji}</span>
                  <div className="min-w-0 flex-1">
                    <p className={`text-sm font-bold ${selected ? "text-coral" : "text-ink"}`}>
                      {meta.label}
                    </p>
                    <p className="text-xs text-ink-faint">{meta.description}</p>
                  </div>
                  {selected && (
                    <span className="text-coral">
                      <Icons.check size={20} />
                    </span>
                  )}
                </button>
              );
            })}
          </div>
          <button
            onClick={startSwiping}
            className="mt-5 w-full rounded-full bg-coral px-6 py-3 text-sm font-bold text-white shadow-lg shadow-coral/30 transition-opacity hover:opacity-90"
          >
            {genderPref ? "Start swiping" : "Skip & start swiping"}
          </button>
          <p className="mt-3 text-[11px] text-ink-faint">
            You can skip this — we&apos;ll show a mix of everything.
          </p>
        </div>
      </div>
    );
  }

  // ── Swipe phase ───────────────────────────────────────────────────────────
  if (phase === "swipe") {
    return (
      <div className={`min-h-screen bg-cream ${transitionClass}`}>
        <GetAppBanner />
        <div className="mx-auto max-w-2xl px-4 py-8">
          <div className="text-center">
            <span className="inline-flex items-center gap-1.5 rounded-full bg-coral-soft px-3 py-1 text-xs font-bold text-coral">
              <Icons.gift size={14} /> {inviterName}&apos;s invite
            </span>
            <h1 className="mt-3 font-display text-3xl font-extrabold leading-tight text-ink">
              Would you want this gifted to you?
            </h1>
            <p className="mx-auto mt-2 max-w-md text-ink-soft">
              Swipe right for yes, left for no. This helps {inviterName} pick the perfect gift for you.
            </p>
          </div>

          <div className="mt-8">
            {deckState === "loading" ? (
              // Challenge deck still arriving — don't flash the local deck.
              <div className="mx-auto h-[460px] w-full max-w-sm animate-pulse rounded-3xl bg-line" />
            ) : (
              <SwipeDeck
                onMatchesReady={onSwipeDone}
                genderPref={genderPref ?? undefined}
                externalDeck={deckState === "ready" && serverDeck ? serverDeck : undefined}
                onSwipe={challengeId ? onChallengeSwipe : undefined}
              />
            )}
          </div>
        </div>
      </div>
    );
  }

  // ── Birthday phase — ask for birthday if the sender didn't pre-set it ─────
  if (phase === "birthday") {
    return (
      <div className={`flex min-h-screen flex-col items-center justify-center bg-cream px-4 ${transitionClass}`}>
        <div className="mx-auto max-w-md rounded-3xl border border-line bg-surface p-6 text-center shadow-lg">
          <span className="inline-flex h-14 w-14 items-center justify-center rounded-full bg-coral-soft text-2xl">🎂</span>
          <h2 className="mt-4 font-display text-xl font-extrabold text-ink">
            One last thing!
          </h2>
          <p className="mt-2 text-sm text-ink-soft">
            Share your birthday so {inviterName} never forgets it. Totally optional!
          </p>
          <label className="mt-4 block">
            <input
              type="date"
              value={birthday}
              onChange={(e) => setBirthday(e.target.value)}
              className="w-full rounded-xl border border-line bg-cream px-4 py-3 text-center text-sm font-medium text-ink outline-none focus:border-coral focus:ring-2 focus:ring-coral/20"
            />
          </label>
          <button
            onClick={finishChallenge}
            className="mt-5 w-full rounded-full bg-coral px-6 py-3 text-sm font-bold text-white shadow-lg shadow-coral/30 transition-opacity hover:opacity-90"
          >
            {birthday ? "Save & see my gifts" : "Skip & see my gifts"}
          </button>
        </div>
      </div>
    );
  }

  // ── Reveal phase — show the gift set; claiming it requires real auth ───────
  return (
    <div className={`min-h-screen bg-cream ${transitionClass}`}>
      <div className="mx-auto max-w-2xl px-4 py-10">
        <div className="text-center">
          <div className="flex justify-center text-coral">
            <Icons.gift size={44} />
          </div>
          <h2 className="mt-3 font-display text-3xl font-extrabold leading-tight text-ink">
            {guestFirst !== "Friend" ? `${guestFirst}, your` : "Your"}
            {occasionLabel ? ` ${occasionLabel}` : ""} gift set is ready
          </h2>
          <p className="mx-auto mt-2 max-w-sm text-ink-soft">
            {occasionLabel
              ? `Based on your swipes, here's what ${inviterName} can shop from for your ${occasionLabel}.`
              : `Based on your swipes, here's what ${inviterName} can shop from.`}
          </p>
        </div>

        <div className="mt-7 grid grid-cols-2 gap-3 sm:grid-cols-3">
          {results.map((p) => (
            <div
              key={p.id}
              className="overflow-hidden rounded-2xl border border-line bg-surface"
            >
              <div
                className="relative aspect-square w-full"
                style={{ background: GRADIENTS[p.grad] }}
              >
                <span className="absolute inset-0 grid place-items-center text-4xl">
                  {p.emoji}
                </span>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={p.image}
                  alt={p.title}
                  loading="lazy"
                  className="absolute inset-0 h-full w-full object-cover"
                  onError={(e) => {
                    e.currentTarget.style.display = "none";
                  }}
                />
              </div>
              <div className="p-2.5">
                <p className="line-clamp-1 text-xs font-semibold text-ink">
                  {shortTitle(p.title)}
                </p>
                <p className="mt-0.5 text-xs text-ink-faint">
                  {p.price ? `$${p.price}` : p.brand}
                </p>
              </div>
            </div>
          ))}
        </div>

        <AppDownloadCTA />

        {clerkEnabled ? (
          <GuestClaimCard inviterName={inviterName} />
        ) : (
          <div className="mt-8 rounded-3xl border border-coral/30 bg-coral-soft/60 p-6 text-center">
            <h3 className="font-display text-xl font-extrabold text-ink">
              Want your own gift set?
            </h3>
            <p className="mx-auto mt-1.5 max-w-sm text-sm text-ink-soft">
              Get matches tailored to you and never miss a gift moment.
            </p>
            <Link
              href="/feed"
              className="mt-5 inline-flex rounded-full bg-coral px-7 py-3 text-sm font-bold text-white shadow-lg shadow-coral/30 transition-opacity hover:opacity-90"
            >
              Explore the feed
            </Link>
          </div>
        )}
      </div>
    </div>
  );
}
