"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { Icons } from "@/components/ui";
import { GRADIENTS, type Grad } from "@/lib/data";
import { PINS, type Pin } from "@/lib/pins";
import { shortTitle } from "@/lib/feed-builder";
import {
  loadSwipes,
  recordSwipe,
  clearSwipes,
  swipeStats,
  swipedIdSet,
  seedKeysFromSwipes,
  swipeVibes,
  localMatchesFromSwipes,
  pinById,
  type SwipeDir,
} from "@/lib/swipes";
import {
  fetchVectorRecommendations,
  isApiConfigured,
  recordInteraction,
  getMyUserId,
  type VectorItem,
} from "@/lib/api";
import { type GenderPref, sortByGenderPref } from "@/lib/gender-prefs";

const GOAL = 5; // "yes" swipes before matches unlock
const THRESHOLD = 90; // px drag distance to commit a swipe

type ResultItem = {
  id: string;
  title: string;
  image: string;
  grad: Grad;
  emoji: string;
  price?: number;
  url?: string;
  brand?: string;
};

function hash(s: string): number {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
  return h;
}

function buildDeck(): Pin[] {
  const swiped = swipedIdSet();
  return PINS.filter((p) => !swiped.has(p.id)).sort(
    (a, b) => hash(a.id) - hash(b.id)
  );
}

function pinToResult(p: Pin): ResultItem {
  return {
    id: p.id,
    title: shortTitle(p.title),
    image: p.image,
    grad: p.grad,
    emoji: p.emoji,
    price: p.price,
    url: p.url,
    brand: p.brand,
  };
}

function vectorToResult(v: VectorItem): ResultItem {
  const pin = pinById(v.postId);
  return {
    id: v.postId,
    title: shortTitle(v.name || pin?.title || "Gift find"),
    image: v.image || pin?.image || "",
    grad: pin?.grad ?? "peach",
    emoji: pin?.emoji ?? "🎁",
    price: pin?.price,
    url: pin?.url,
    brand: v.author || pin?.brand,
  };
}

export function SwipeDeck({
  compact = false,
  onMatchesReady,
  genderPref,
  externalDeck,
  onSwipe,
}: {
  compact?: boolean;
  onMatchesReady?: () => void;
  genderPref?: GenderPref;
  /** Server-built deck (challenge flow) — used as-is: the Lambda already
   *  quality-filtered, banded, and shuffled it, so no local reordering. */
  externalDeck?: Pin[];
  /** Per-swipe callback with dwell time — the challenge page collects these
   *  to POST /challenges/{id}/response. */
  onSwipe?: (id: string, dir: SwipeDir, dwellMs: number) => void;
}) {
  const [mounted, setMounted] = useState(false);
  const [deck, setDeck] = useState<Pin[]>([]);
  const [idx, setIdx] = useState(0);
  const [drag, setDrag] = useState({ dx: 0, dy: 0 });
  const [dragging, setDragging] = useState(false);
  const [fly, setFly] = useState<SwipeDir | null>(null);
  const [stats, setStats] = useState({ yes: 0, no: 0, total: 0 });
  const [phase, setPhase] = useState<"swipe" | "results">("swipe");
  const [results, setResults] = useState<ResultItem[] | null>(null);
  const [resultSource, setResultSource] = useState<string>("");
  const [loadingResults, setLoadingResults] = useState(false);

  const startRef = useRef<{ x: number; y: number } | null>(null);
  // Track when the current card was first shown (for dwell time measurement)
  const cardShownAtRef = useRef<number>(0);

  useEffect(() => {
    // SSR-safe: read localStorage only after mount.
    const rawDeck = externalDeck?.length ? externalDeck : buildDeck();
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setDeck(!externalDeck?.length && genderPref ? sortByGenderPref(rawDeck, genderPref) : rawDeck);
    setStats(externalDeck?.length ? { yes: 0, no: 0, total: 0 } : swipeStats());
    setMounted(true);
    cardShownAtRef.current = Date.now();
  }, [genderPref, externalDeck]);

  const eligible = stats.yes >= GOAL || (mounted && deck.length > 0 && idx >= deck.length);

  const commit = useCallback(
    (dir: SwipeDir) => {
      const pin = deck[idx];
      if (!pin || fly) return;
      setFly(dir);
      // Calculate dwell time: how long the user looked at this card before swiping
      const dwellMs = Date.now() - cardShownAtRef.current;
      recordSwipe(pin.id, dir, dwellMs);
      onSwipe?.(pin.id, dir, dwellMs);
      // Persist the swipe to the DynamoDB interactions table (fire-and-forget,
      // no-ops when the API isn't configured). A "yes" is a positive taste
      // signal -> `like` (seeds the vector recommender + excludes from feed);
      // a "no" is recorded as `seen` so it stops reappearing without becoming a
      // positive seed.
      recordInteraction(getMyUserId(), pin.id, dir === "yes" ? "like" : "seen");
      if (externalDeck?.length) {
        // Challenge session: count only this deck's swipes (global stats
        // include past local sessions).
        setStats((s) => ({
          yes: s.yes + (dir === "yes" ? 1 : 0),
          no: s.no + (dir === "no" ? 1 : 0),
          total: s.total + 1,
        }));
      } else {
        setStats(swipeStats());
      }
      window.setTimeout(() => {
        setIdx((i) => i + 1);
        setDrag({ dx: 0, dy: 0 });
        setFly(null);
        // Reset dwell timer for next card
        cardShownAtRef.current = Date.now();
      }, 230);
    },
    [deck, idx, fly, onSwipe, externalDeck]
  );

  const undo = useCallback(() => {
    if (idx === 0 || fly) return;
    const prev = deck[idx - 1];
    if (!prev) return;
    // Drop the most recent decision for that pin and step back.
    const next = loadSwipes().filter((s) => s.id !== prev.id);
    try {
      localStorage.setItem("giftmaxxing_swipes", JSON.stringify(next));
      window.dispatchEvent(new Event("giftmaxxing:swipes"));
    } catch {
      // ignore
    }
    setIdx((i) => Math.max(0, i - 1));
    setStats(swipeStats());
  }, [deck, idx, fly]);

  // Keyboard: ← pass, → want it.
  useEffect(() => {
    if (phase !== "swipe") return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "ArrowLeft") commit("no");
      else if (e.key === "ArrowRight") commit("yes");
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [commit, phase]);

  const onPointerDown = (e: React.PointerEvent) => {
    if (fly) return;
    startRef.current = { x: e.clientX, y: e.clientY };
    setDragging(true);
    e.currentTarget.setPointerCapture(e.pointerId);
  };
  const onPointerMove = (e: React.PointerEvent) => {
    if (!dragging || !startRef.current) return;
    setDrag({
      dx: e.clientX - startRef.current.x,
      dy: (e.clientY - startRef.current.y) * 0.4,
    });
  };
  const onPointerUp = () => {
    if (!dragging) return;
    setDragging(false);
    startRef.current = null;
    if (drag.dx > THRESHOLD) commit("yes");
    else if (drag.dx < -THRESHOLD) commit("no");
    else setDrag({ dx: 0, dy: 0 });
  };

  const loadResults = useCallback(async () => {
    if (onMatchesReady) {
      onMatchesReady();
      return;
    }
    setLoadingResults(true);
    setPhase("results");
    const seeds = seedKeysFromSwipes(8);
    const vibes = swipeVibes(5);
    let items: ResultItem[] = [];
    let source = "from your swipes";
    try {
      if (isApiConfigured() && seeds.length) {
        const res = await fetchVectorRecommendations({ seedKeys: seeds, vibes, limit: 12 });
        if (res.items.length) {
          items = res.items.map(vectorToResult);
          source = res.source === "vector" ? "S3 Vectors · your swipe taste" : "from your swipe taste";
        }
      }
    } catch {
      // fall through to local ranking
    }
    if (!items.length) {
      items = localMatchesFromSwipes(12).map(pinToResult);
      source = "from your swipes (offline match)";
    }
    setResults(items);
    setResultSource(source);
    setLoadingResults(false);
  }, [onMatchesReady]);

  const startOver = useCallback(() => {
    clearSwipes();
    const rawDeck = buildDeck();
    setDeck(genderPref ? sortByGenderPref(rawDeck, genderPref) : rawDeck);
    setIdx(0);
    setDrag({ dx: 0, dy: 0 });
    setFly(null);
    setStats({ yes: 0, no: 0, total: 0 });
    setResults(null);
    setPhase("swipe");
  }, [genderPref]);

  if (!mounted) {
    return <div className="mx-auto h-[460px] w-full max-w-sm animate-pulse rounded-3xl bg-line" />;
  }

  if (phase === "results") {
    return (
      <ResultsView
        results={results}
        source={resultSource}
        loading={loadingResults}
        stats={stats}
        onKeepSwiping={() => setPhase("swipe")}
        onStartOver={startOver}
      />
    );
  }

  const deckEmpty = idx >= deck.length;
  const stamp = Math.max(0, Math.min(1, Math.abs(drag.dx) / THRESHOLD));

  return (
    <div className="mx-auto w-full max-w-sm">
      {/* progress */}
      {!compact && (
        <div className="mb-4 flex items-center justify-between text-sm">
          <span className="font-semibold text-ink">
            <span className="text-coral">♥ {stats.yes}</span> want · {stats.no} pass
          </span>
          {/* Undo rewinds localStorage swipes — not meaningful for a
              server-deck challenge session, so it's hidden there. */}
          {!externalDeck?.length && (
            <button
              onClick={undo}
              disabled={idx === 0}
              className="flex items-center gap-1 text-ink-faint transition-colors hover:text-ink disabled:opacity-40"
            >
              <Icons.back size={15} /> Undo
            </button>
          )}
        </div>
      )}

      {/* card stack */}
      <div className="relative mx-auto h-[460px] w-full select-none">
        {deckEmpty ? (
          <div className="grid h-full place-items-center rounded-3xl border border-dashed border-line bg-surface/60 px-6 text-center">
            <div>
              <p className="text-4xl">🎉</p>
              <p className="mt-3 font-display text-lg font-bold text-ink">That&apos;s everything!</p>
              <p className="mt-1 text-sm text-ink-soft">You swiped all {deck.length} finds.</p>
            </div>
          </div>
        ) : (
          deck.slice(idx, idx + 3).map((pin, pos) => {
            const isTop = pos === 0;
            const dir = fly === "yes" ? 1 : -1;
            let transform = `translateY(${pos * 10}px) scale(${1 - pos * 0.04})`;
            let transition = "transform .25s ease";
            let opacity = 1;
            if (isTop) {
              if (fly) {
                transform = `translateX(${dir * 140}%) rotate(${dir * 18}deg)`;
                transition = "transform .23s ease, opacity .23s ease";
                opacity = 0;
              } else if (dragging || drag.dx || drag.dy) {
                transform = `translate(${drag.dx}px, ${drag.dy}px) rotate(${drag.dx / 18}deg)`;
                transition = dragging ? "none" : "transform .25s ease";
              }
            }
            return (
              <article
                key={pin.id}
                onPointerDown={isTop ? onPointerDown : undefined}
                onPointerMove={isTop ? onPointerMove : undefined}
                onPointerUp={isTop ? onPointerUp : undefined}
                onPointerCancel={isTop ? onPointerUp : undefined}
                style={{ transform, transition, opacity, zIndex: 30 - pos, touchAction: "none" }}
                className={`absolute inset-0 overflow-hidden rounded-3xl border border-line bg-surface shadow-lg ${
                  isTop ? "cursor-grab active:cursor-grabbing" : ""
                }`}
              >
                <div className="relative h-[330px] w-full" style={{ background: GRADIENTS[pin.grad] }}>
                  <span className="absolute inset-0 grid place-items-center text-7xl">{pin.emoji}</span>
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img
                    src={pin.image}
                    alt={pin.title}
                    draggable={false}
                    className="absolute inset-0 h-full w-full object-cover"
                    onError={(e) => { e.currentTarget.style.display = "none"; }}
                  />
                  {/* drag stamps */}
                  {isTop && (
                    <>
                      <span
                        style={{ opacity: drag.dx > 12 ? stamp : 0 }}
                        className="absolute left-4 top-4 rotate-[-12deg] rounded-xl border-4 border-emerald-500 px-3 py-1 text-xl font-extrabold text-emerald-500"
                      >
                        WANT ♥
                      </span>
                      <span
                        style={{ opacity: drag.dx < -12 ? stamp : 0 }}
                        className="absolute right-4 top-4 rotate-[12deg] rounded-xl border-4 border-rose-500 px-3 py-1 text-xl font-extrabold text-rose-500"
                      >
                        PASS
                      </span>
                    </>
                  )}
                </div>
                <div className="flex h-[130px] flex-col justify-between p-4">
                  <div>
                    <p className="line-clamp-2 font-semibold leading-snug text-ink">{shortTitle(pin.title)}</p>
                    <p className="mt-1 text-sm text-ink-faint">{pin.brand}</p>
                  </div>
                  <div className="flex items-center justify-between">
                    <span className="font-display text-lg font-bold text-ink">${pin.price}</span>
                    <span className="rounded-full bg-cream px-2.5 py-1 text-xs font-semibold capitalize text-ink-soft">
                      {pin.category}
                    </span>
                  </div>
                </div>
              </article>
            );
          })
        )}
      </div>

      {/* actions */}
      {!deckEmpty && (
        <div className="mt-5 flex items-center justify-center gap-5">
          <button
            onClick={() => commit("no")}
            disabled={!!fly}
            aria-label="Pass"
            className="grid h-16 w-16 place-items-center rounded-full border border-line bg-surface text-rose-500 shadow-sm transition-transform hover:scale-105 active:scale-95 disabled:opacity-50"
          >
            <Icons.close size={30} />
          </button>
          <button
            onClick={() => commit("yes")}
            disabled={!!fly}
            aria-label="Want it"
            className="grid h-20 w-20 place-items-center rounded-full bg-coral text-white shadow-lg shadow-coral/30 transition-transform hover:scale-105 active:scale-95 disabled:opacity-50"
          >
            <Icons.heartFill size={36} />
          </button>
        </div>
      )}

      {/* unlock matches */}
      {!compact && (
        <div className="mt-6 text-center">
          {eligible ? (
            <button
              onClick={loadResults}
              className="inline-flex items-center gap-2 rounded-full bg-ink px-6 py-3 text-sm font-bold text-white transition-opacity hover:opacity-90"
            >
              <Icons.sparkle size={16} /> See your gift matches
            </button>
          ) : (
            <p className="text-sm text-ink-soft">
              Tap <span className="font-semibold text-coral">♥</span> on {GOAL - stats.yes} more to unlock your matches
            </p>
          )}
        </div>
      )}
    </div>
  );
}

function ResultsView({
  results,
  source,
  loading,
  stats,
  onKeepSwiping,
  onStartOver,
}: {
  results: ResultItem[] | null;
  source: string;
  loading: boolean;
  stats: { yes: number; no: number; total: number };
  onKeepSwiping: () => void;
  onStartOver: () => void;
}) {
  return (
    <div className="mx-auto w-full max-w-xl">
      <div className="text-center">
        <h2 className="font-display text-2xl font-extrabold text-ink">Your gift matches</h2>
        <p className="mt-1 text-sm text-ink-soft">
          Ranked {source} — trained on {stats.yes} likes across {stats.total} swipes.
        </p>
      </div>

      {loading ? (
        <div className="mt-6 grid grid-cols-2 gap-3 sm:grid-cols-3">
          {Array.from({ length: 6 }).map((_, i) => (
            <div key={i} className="aspect-[3/4] animate-pulse rounded-2xl bg-line" />
          ))}
        </div>
      ) : (
        <div className="mt-6 grid grid-cols-2 gap-3 sm:grid-cols-3">
          {(results ?? []).map((r) => (
            <a
              key={r.id}
              href={r.url || "#"}
              target={r.url ? "_blank" : undefined}
              rel="noreferrer"
              className="group overflow-hidden rounded-2xl border border-line bg-surface transition-shadow hover:shadow-md"
            >
              <div className="relative aspect-square w-full" style={{ background: GRADIENTS[r.grad] }}>
                <span className="absolute inset-0 grid place-items-center text-4xl">{r.emoji}</span>
                {r.image && (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img
                    src={r.image}
                    alt={r.title}
                    loading="lazy"
                    className="absolute inset-0 h-full w-full object-cover transition-transform group-hover:scale-105"
                    onError={(e) => { e.currentTarget.style.display = "none"; }}
                  />
                )}
              </div>
              <div className="p-2.5">
                <p className="line-clamp-1 text-xs font-semibold text-ink">{r.title}</p>
                <p className="mt-0.5 text-xs text-ink-faint">{r.price ? `$${r.price}` : r.brand}</p>
              </div>
            </a>
          ))}
        </div>
      )}

      <div className="mt-7 flex items-center justify-center gap-3">
        <button
          onClick={onKeepSwiping}
          className="rounded-full bg-coral px-5 py-2.5 text-sm font-bold text-white transition-opacity hover:opacity-90"
        >
          Keep swiping
        </button>
        <button
          onClick={onStartOver}
          className="rounded-full border border-line bg-surface px-5 py-2.5 text-sm font-bold text-ink hover:bg-coral-soft"
        >
          Start over
        </button>
      </div>
    </div>
  );
}
