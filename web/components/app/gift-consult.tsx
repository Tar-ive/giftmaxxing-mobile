"use client";

// The Gift Concierge consult — shared by /gift (public page) and /onboarding
// (where the consult IS onboarding: same questions, and the answers double as
// the new user's taste profile via deriveProfileFromConsult).
//
// The flow: a few sharp questions (budget optional — "just find the gift"
// works) → ranked picks from the real catalog → either buy the top pick, or
// double-check it first: we mint a mode="verify" challenge whose deck hides
// the pick among ~14 cards. If the recipient swipes right on it, the server
// reports a confirmed match — they chose it without knowing it was the ask.

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { ChatFlow, type ChatAnswers, type ChatStep } from "@/components/app/chat-flow";
import { Maxi, Icons } from "@/components/ui";
import { GRADIENTS } from "@/lib/data";
import {
  createChallenge,
  fetchChallenge,
  fetchFeed,
  isApiConfigured,
  type ChallengePublic,
} from "@/lib/api";
import { hiResImage } from "@/lib/images";
import { outboundAffiliateUrl, amazonSearchUrl, AFFILIATE_REL } from "@/lib/affiliate";
import { buildInviteUrl } from "@/lib/invite";
import { getCurrentUser } from "@/lib/identity";
import { saveProfile } from "@/lib/onboarding";
import type { Post } from "@/lib/social";
import {
  CONSULT_RELATIONS,
  CONSULT_OCCASIONS,
  CONSULT_WORLDS,
  CONSULT_KEEPERS,
  MOVE_VERDICT_META,
  type ConsultAnswers,
  type ConsultRelation,
  type KeeperKey,
  type WorldKey,
  type RankedGift,
  consultFeedOpts,
  deriveProfileFromConsult,
  parseBudgetText,
  rankGifts,
} from "@/lib/consult";

// ── The consult script (see lib/consult.ts for the metadata) ─────────────────

const BUDGET_CHIPS = [25, 50, 100, 250].map((n) => ({ value: String(n), label: `Under $${n}` }));

function firstName(a: ChatAnswers): string | null {
  const n = typeof a.name === "string" ? a.name.trim() : "";
  return n ? n.split(/\s+/)[0] : null;
}
const they = (a: ChatAnswers) => firstName(a) ?? "they";
const them = (a: ChatAnswers) => firstName(a) ?? "them";

// Onboarding-only opener: this one is about the USER, not the recipient — it
// sets the recipient facet their own feed leans toward (him → "men", …).
const GENDER_STEP: ChatStep = {
  id: "genderPref",
  prompts: () => [
    "One thing about YOU first — whose gifts should your feed lean toward?",
    "This shapes what I show you day-to-day. The consults work for anyone either way.",
  ],
  input: "chips",
  options: [
    { value: "him", label: "Gifts for him", emoji: "🤵" },
    { value: "her", label: "Gifts for her", emoji: "👩" },
    { value: "any", label: "Mix of everyone", emoji: "🎁" },
  ],
};

const STEPS: ChatStep[] = [
  {
    id: "relation",
    prompts: () => ["First — who are we gifting?"],
    input: "chips",
    options: Object.entries(CONSULT_RELATIONS).map(([value, m]) => ({
      value,
      label: m.label,
      emoji: m.emoji,
    })),
  },
  {
    id: "name",
    prompts: () => ["What do you call them? First name is plenty."],
    input: "text",
    placeholder: "Their name",
    skippable: true,
    skipLabel: "Rather not say",
    parseText: (t) => {
      const clean = t.replace(/[^\p{L}\p{N} '-]/gu, "").trim().slice(0, 24);
      return clean ? { value: clean, label: clean } : null;
    },
    rejectText: "Just a name — letters work best 😄",
  },
  {
    id: "occasion",
    prompts: (a) => [`Got it. What's the occasion for ${them(a)}?`],
    input: "chips",
    options: CONSULT_OCCASIONS.map((o) => ({ value: o.key, label: o.label, emoji: o.emoji })),
  },
  {
    id: "budget",
    prompts: () => [
      "What's the budget? Tap one or type it — \"around $80\" works.",
      "No number in mind? Skip it — I'll judge on the gift, not the price.",
    ],
    input: "chips",
    allowText: true,
    skippable: true,
    skipLabel: "No budget — just find it",
    options: BUDGET_CHIPS,
    placeholder: "e.g. around $80",
    parseText: (t) => {
      const n = parseBudgetText(t);
      return n ? { value: String(n), label: `About $${n}` } : null;
    },
    rejectText: "Give me a number — \"$60\" or \"around 100\" both work. Or skip it.",
  },
  {
    id: "worlds",
    prompts: (a) => [
      `Now the part that matters: what is ${they(a)} actually into?`,
      "Pick everything that's true — the overlap is where good gifts hide.",
    ],
    input: "multichips",
    minPicks: 1,
    confirmLabel: "That's them",
    options: Object.entries(CONSULT_WORLDS).map(([value, m]) => ({
      value,
      label: m.label,
      emoji: m.emoji,
    })),
  },
  {
    id: "sunday",
    prompts: (a) => [
      `Picture ${them(a)} on a free Sunday afternoon, nothing planned.`,
      "What are they doing? One line, in your words.",
    ],
    input: "text",
    placeholder: "e.g. baking bread with a podcast on",
    skippable: true,
    skipLabel: "Honestly, no idea",
  },
  {
    id: "keeper",
    prompts: (a) => [
      "Last one, and it's my favorite question:",
      `Think of the last time ${they(a)} moved. What came with ${them(a)} — no question, first box packed?`,
    ],
    input: "chips",
    options: Object.entries(CONSULT_KEEPERS).map(([value, m]) => ({
      value,
      label: m.label,
      emoji: m.emoji,
    })),
  },
];

// The move test is the app's PRIVATE quality bar (it drives rankGifts) — Maxi
// doesn't lecture about it up front; the "keeper" question carries the idea.
const INTRO = [
  "Hey — I'm Maxi. I find gifts people actually keep.",
  "A few quick questions about your person and I'll pull real options.",
];

const INTRO_ONBOARDING = [
  "Hey — I'm Maxi, your gift concierge. This is the whole app: you tell me about a person, I find the gift.",
  "Let's do your first consult right now — think of someone you owe a gift.",
];

// ── Component ────────────────────────────────────────────────────────────────

type Phase = "chat" | "thinking" | "results";

export function GiftConsult({ onboarding = false }: { onboarding?: boolean }) {
  const router = useRouter();
  const [phase, setPhase] = useState<Phase>("chat");
  const [answers, setAnswers] = useState<ConsultAnswers | null>(null);
  const [gifts, setGifts] = useState<RankedGift[]>([]);
  const [pool, setPool] = useState<Post[]>([]);
  const [flowKey, setFlowKey] = useState(0); // remount ChatFlow on "start over"
  const genderPrefRef = useRef<"him" | "her" | "any" | undefined>(undefined);

  const runConsult = useCallback(
    async (a: ConsultAnswers) => {
      setAnswers(a);
      setPhase("thinking");
      // Onboarding: the consult answers ARE the taste profile — persist it so
      // the gate opens and the feed personalizes from the same signals.
      if (onboarding) {
        saveProfile(deriveProfileFromConsult(a, getCurrentUser().name, genderPrefRef.current));
      }
      let posts: Post[] = [];
      if (isApiConfigured()) {
        const opts = consultFeedOpts(a);
        // Two pulls: one aimed at their facets, one broad for variety — the
        // client-side ranker (move test + interests + budget) does the rest.
        const [targeted, broad] = await Promise.all([
          fetchFeed(opts).catch(() => ({ posts: [] as Post[], cursor: null })),
          fetchFeed({ budget: a.budget, limit: 50 }).catch(() => ({ posts: [] as Post[], cursor: null })),
        ]);
        posts = [...targeted.posts, ...broad.posts];
      }
      setPool(posts);
      setGifts(rankGifts(posts, a));
      // Let the "reading them back" beat land before the reveal.
      window.setTimeout(() => setPhase("results"), 1400);
    },
    [onboarding],
  );

  const onComplete = useCallback(
    (raw: ChatAnswers) => {
      genderPrefRef.current =
        raw.genderPref === "him" || raw.genderPref === "her" || raw.genderPref === "any"
          ? raw.genderPref
          : undefined;
      const budgetNum = Number(raw.budget);
      const a: ConsultAnswers = {
        relation: (raw.relation as ConsultRelation) ?? "other",
        name: typeof raw.name === "string" ? raw.name : undefined,
        occasion: typeof raw.occasion === "string" ? raw.occasion : "any",
        budget: Number.isFinite(budgetNum) && budgetNum > 0 ? budgetNum : undefined,
        worlds: Array.isArray(raw.worlds) ? (raw.worlds as WorldKey[]) : [],
        sunday: typeof raw.sunday === "string" ? raw.sunday : undefined,
        keeper: (raw.keeper as KeeperKey) ?? "light",
      };
      void runConsult(a);
    },
    [runConsult],
  );

  const rebudget = useCallback(
    (budget?: number) => {
      if (!answers) return;
      const next = { ...answers, budget };
      setAnswers(next);
      setGifts(rankGifts(pool, next));
    },
    [answers, pool],
  );

  const reset = useCallback(() => {
    setPhase("chat");
    setAnswers(null);
    setGifts([]);
    setPool([]);
    setFlowKey((k) => k + 1);
  }, []);

  return (
    <>
      {phase === "chat" && (
        <div className="min-h-0 flex-1">
          <ChatFlow
            key={flowKey}
            steps={onboarding ? [GENDER_STEP, ...STEPS] : STEPS}
            intro={onboarding ? INTRO_ONBOARDING : INTRO}
            onComplete={onComplete}
          />
        </div>
      )}

      {phase === "thinking" && answers && <Thinking answers={answers} />}

      {phase === "results" && answers && (
        <>
          <Results answers={answers} gifts={gifts} onReset={reset} onRebudget={rebudget} />
          {onboarding && (
            <button
              onClick={() => router.push("/feed")}
              className="mt-6 w-full rounded-full bg-ink py-3.5 text-sm font-bold text-cream transition-opacity hover:opacity-90"
            >
              Start exploring the app →
            </button>
          )}
        </>
      )}
    </>
  );
}

// ── Thinking beat: read their person back to them while we rank ──────────────

function Thinking({ answers }: { answers: ConsultAnswers }) {
  const who = answers.name?.trim() || CONSULT_RELATIONS[answers.relation].label.toLowerCase();
  const worlds = answers.worlds
    .slice(0, 3)
    .map((w) => CONSULT_WORLDS[w]?.label.toLowerCase())
    .filter(Boolean)
    .join(", ");
  return (
    <div className="flex flex-1 flex-col items-center justify-center py-16 text-center animate-rise">
      <div className="animate-float"><Maxi size={64} /></div>
      <p className="mt-6 max-w-sm font-display text-xl font-bold text-ink">
        Okay — {who}, {worlds || "their world"},{" "}
        {answers.budget ? `$${answers.budget} to spend` : "budget open"}.
      </p>
      <p className="mt-2 text-sm text-ink-soft">
        Running the catalog through the move test…
      </p>
      <div className="mt-6 flex gap-1.5">
        {[0, 1, 2].map((i) => (
          <span
            key={i}
            className="h-2 w-2 animate-bounce rounded-full bg-coral"
            style={{ animationDelay: `${i * 150}ms` }}
          />
        ))}
      </div>
    </div>
  );
}

// ── Results: top pick + shortlist, every card wears its move-test verdict ────

function Results({
  answers,
  gifts,
  onReset,
  onRebudget,
}: {
  answers: ConsultAnswers;
  gifts: RankedGift[];
  onReset: () => void;
  onRebudget: (n?: number) => void;
}) {
  const who = answers.name?.trim() || "your person";
  const [top, ...rest] = gifts;

  return (
    <div className="animate-rise">
      {/* The bar, stated */}
      <div className="mb-4 flex items-center gap-3 rounded-2xl border border-line bg-surface/70 px-4 py-3">
        <span className="text-xl">📦</span>
        <p className="text-[13px] leading-snug text-ink-soft">
          <span className="font-bold text-ink">The move test:</span> everything below is
          something {who} would pack, not purge, when they next move.
        </p>
      </div>

      {gifts.length === 0 ? (
        <EmptyState answers={answers} onReset={onReset} />
      ) : (
        <>
          {top && <TopPick gift={top} />}
          {top && <VerifyPanel top={top} answers={answers} />}

          {rest.length > 0 && (
            <>
              <p className="mb-3 mt-6 text-xs font-semibold uppercase tracking-widest text-ink-faint">
                Also strong
              </p>
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
                {rest.map((g) => (
                  <GiftCard key={g.post.id} gift={g} />
                ))}
              </div>
            </>
          )}

          {/* Refine */}
          <div className="mt-8 rounded-2xl border border-line bg-surface p-4">
            <p className="text-sm font-bold text-ink">Not quite it?</p>
            <div className="mt-3 flex flex-wrap items-center gap-2">
              {[25, 50, 100, 250]
                .filter((n) => n !== answers.budget)
                .map((n) => (
                  <button
                    key={n}
                    onClick={() => onRebudget(n)}
                    className="rounded-full border-2 border-line bg-surface px-4 py-2 text-sm font-semibold text-ink-soft transition-all hover:border-ink/25 hover:text-ink active:scale-95"
                  >
                    Try under ${n}
                  </button>
                ))}
              {answers.budget != null && (
                <button
                  onClick={() => onRebudget(undefined)}
                  className="rounded-full border-2 border-line bg-surface px-4 py-2 text-sm font-semibold text-ink-soft transition-all hover:border-ink/25 hover:text-ink active:scale-95"
                >
                  Forget the budget
                </button>
              )}
              <button
                onClick={onReset}
                className="rounded-full bg-ink px-4 py-2 text-sm font-bold text-cream transition-opacity hover:opacity-90 active:scale-95"
              >
                ↺ New consult
              </button>
            </div>
          </div>
        </>
      )}
    </div>
  );
}

// ── The double-check: hide the pick in a 14-card swipe deck ──────────────────
// createChallenge(mode:"verify", postId) → the server builds a deck of similar
// items and slips the pick in unlabeled. The recipient just swipes; GET then
// reports whether the hidden card got a right-swipe (a confirmed match).

function VerifyPanel({ top, answers }: { top: RankedGift; answers: ConsultAnswers }) {
  const [state, setState] = useState<"idle" | "creating" | "ready" | "error">("idle");
  const [url, setUrl] = useState<string | null>(null);
  const [challengeId, setChallengeId] = useState<string | null>(null);
  const [verify, setVerify] = useState<NonNullable<ChallengePublic["verify"]> | null>(null);
  const [copied, setCopied] = useState(false);
  const who = answers.name?.trim() || "them";

  const start = async () => {
    setState("creating");
    const user = getCurrentUser();
    const id = await createChallenge({
      senderId: user.id,
      postId: top.post.id,
      mode: "verify",
      inviterName: user.name,
      to: answers.name,
      occasion: answers.occasion !== "any" ? answers.occasion : undefined,
    });
    if (!id) {
      setState("error");
      return;
    }
    setChallengeId(id);
    setUrl(buildInviteUrl(user.name || "A friend", { challengeId: id, senderId: user.id, to: answers.name }));
    setState("ready");
  };

  // Poll the aggregate verify summary while the panel is live.
  useEffect(() => {
    if (!challengeId) return;
    let alive = true;
    const tick = async () => {
      const ch = await fetchChallenge(challengeId);
      if (alive && ch?.verify) setVerify(ch.verify);
    };
    void tick();
    const t = window.setInterval(tick, 8000);
    return () => {
      alive = false;
      window.clearInterval(t);
    };
  }, [challengeId]);

  const share = async () => {
    if (!url) return;
    if (navigator.share) {
      try {
        await navigator.share({ title: "Quick swipe game 🎁", url });
        return;
      } catch {
        /* fall through to copy */
      }
    }
    await navigator.clipboard.writeText(url);
    setCopied(true);
    window.setTimeout(() => setCopied(false), 2000);
  };

  if (!isApiConfigured()) return null;

  return (
    <div className="mt-3 rounded-2xl border border-line bg-surface p-4">
      {state === "idle" || state === "creating" || state === "error" ? (
        <>
          <p className="text-sm font-bold text-ink">Not 100% sure? Ask {who} — sneakily.</p>
          <p className="mt-1 text-[13px] leading-snug text-ink-soft">
            I&rsquo;ll hide this pick in a deck of 14 cards. {answers.name?.trim() || "They"}{" "}
            just swipes what they like — they&rsquo;ll never know which card was the ask. A
            right-swipe on your pick = confirmed match.
          </p>
          <button
            onClick={start}
            disabled={state === "creating"}
            className="mt-3 inline-flex items-center gap-2 rounded-full bg-ink px-5 py-2.5 text-sm font-bold text-cream transition-opacity hover:opacity-90 disabled:opacity-50"
          >
            <Icons.share size={14} />
            {state === "creating" ? "Building the deck…" : "Double-check with a swipe game"}
          </button>
          {state === "error" && (
            <p className="mt-2 text-xs font-semibold text-coral">
              Couldn&rsquo;t build the deck — try again in a minute.
            </p>
          )}
        </>
      ) : (
        <>
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <p className="text-sm font-bold text-ink">Swipe game is live 🎳</p>
              <p className="mt-1 text-[13px] leading-snug text-ink-soft">
                Send it to {who}. Your pick is hidden among 14 cards.
              </p>
            </div>
            <button
              onClick={share}
              className="shrink-0 rounded-full bg-coral px-4 py-2 text-xs font-bold text-white transition-opacity hover:opacity-90"
            >
              {copied ? "Copied!" : "Share link"}
            </button>
          </div>
          <VerifyStatus verify={verify} who={who} />
        </>
      )}
    </div>
  );
}

function VerifyStatus({
  verify,
  who,
}: {
  verify: NonNullable<ChallengePublic["verify"]> | null;
  who: string;
}) {
  if (!verify || verify.responses === 0) {
    return (
      <p className="mt-3 flex items-center gap-2 rounded-xl bg-cream-2 px-3 py-2.5 text-[13px] font-semibold text-ink-soft">
        <span className="h-2 w-2 animate-pulse rounded-full bg-butter-2" />
        Waiting for {who} to swipe — this updates live.
      </p>
    );
  }
  if (verify.matched) {
    return (
      <p className="mt-3 rounded-xl bg-sage-1 px-3 py-2.5 text-[13px] font-bold text-ink">
        🎯 Confirmed match — {verify.by || who} swiped right on your pick without knowing it
        was the ask. Buy it.
      </p>
    );
  }
  const line =
    verify.label === "love"
      ? `No direct hit, but their taste runs hot for it — strong buy signal.`
      : verify.label === "like"
        ? `They didn't pick it directly, but everything they liked sits close to it.`
        : `They passed it by — their swipes point somewhere else. Try another pick.`;
  return (
    <p className="mt-3 rounded-xl bg-cream-2 px-3 py-2.5 text-[13px] font-semibold text-ink-soft">
      {verify.responses} response{verify.responses === 1 ? "" : "s"} in · {line}
    </p>
  );
}

function verdictBadge(g: RankedGift) {
  const meta = MOVE_VERDICT_META[g.move.verdict];
  return (
    <span
      className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-bold ${
        g.move.verdict === "pack" ? "bg-sage-1 text-ink" : "bg-butter-1 text-ink"
      }`}
      title={g.move.reasons.join(" · ")}
    >
      {meta.emoji} {meta.label}
    </span>
  );
}

function buyHref(g: RankedGift): string {
  return outboundAffiliateUrl(g.post.productUrl, {
    name: g.post.product.name,
    brand: g.post.product.brand,
  });
}

function merchantLabel(g: RankedGift): string {
  try {
    const u = new URL(g.post.productUrl ?? "");
    return u.hostname.replace(/^www\./, "");
  } catch {
    return g.post.product.brand;
  }
}

function TopPick({ gift }: { gift: RankedGift }) {
  const p = gift.post.product;
  const img = hiResImage(p.image);
  return (
    <a
      href={buyHref(gift)}
      target="_blank"
      rel={AFFILIATE_REL}
      className="hover-lift block overflow-hidden rounded-3xl border border-line bg-surface shadow-sm"
    >
      <div className="relative aspect-[4/3] w-full overflow-hidden" style={{ background: GRADIENTS[p.grad] }}>
        {img ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={img} alt={p.name} className="h-full w-full object-cover" loading="lazy" />
        ) : (
          <span className="grid h-full w-full place-items-center text-6xl">{p.emoji}</span>
        )}
        <span className="absolute left-3 top-3 rounded-full bg-ink/85 px-3 py-1 text-[11px] font-bold text-cream backdrop-blur">
          ⭐ The pick
        </span>
      </div>
      <div className="p-4">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <p className="truncate text-[15px] font-bold text-ink">{p.name}</p>
            <p className="text-xs text-ink-faint">{merchantLabel(gift)}</p>
          </div>
          <p className="shrink-0 text-lg font-extrabold text-ink">${p.price}</p>
        </div>
        <p className="mt-2 text-[13px] leading-snug text-ink-soft">
          {gift.why} — {gift.move.reasons[0]}.
        </p>
        <div className="mt-3 flex items-center justify-between">
          {verdictBadge(gift)}
          <span className="inline-flex items-center gap-1.5 rounded-full bg-coral px-4 py-2 text-xs font-bold text-white">
            <Icons.gift size={14} /> Get it
          </span>
        </div>
      </div>
    </a>
  );
}

function GiftCard({ gift }: { gift: RankedGift }) {
  const p = gift.post.product;
  const img = hiResImage(p.image);
  return (
    <a
      href={buyHref(gift)}
      target="_blank"
      rel={AFFILIATE_REL}
      className="hover-lift flex flex-col overflow-hidden rounded-2xl border border-line bg-surface shadow-sm"
    >
      <div className="relative aspect-square w-full overflow-hidden" style={{ background: GRADIENTS[p.grad] }}>
        {img ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={img} alt={p.name} className="h-full w-full object-cover" loading="lazy" />
        ) : (
          <span className="grid h-full w-full place-items-center text-4xl">{p.emoji}</span>
        )}
      </div>
      <div className="flex flex-1 flex-col p-2.5">
        <p className="line-clamp-2 text-xs font-bold leading-snug text-ink">{p.name}</p>
        <p className="mt-0.5 truncate text-[10px] text-ink-faint">{merchantLabel(gift)}</p>
        <div className="mt-auto flex items-center justify-between pt-2">
          <span className="text-[13px] font-extrabold text-ink">${p.price}</span>
          {verdictBadge(gift)}
        </div>
      </div>
    </a>
  );
}

// Never a dead end: if the catalog is unreachable or too thin for this person,
// hand them tagged searches for each of their worlds instead.
function EmptyState({ answers, onReset }: { answers: ConsultAnswers; onReset: () => void }) {
  const links = useMemo(() => {
    const who = CONSULT_RELATIONS[answers.relation].label.replace(/^my /i, "").toLowerCase();
    const worlds = answers.worlds.length ? answers.worlds : (["home"] as WorldKey[]);
    return worlds.slice(0, 4).map((w) => {
      const m = CONSULT_WORLDS[w];
      const budgetSuffix = answers.budget ? ` under $${answers.budget}` : "";
      return {
        label: `${m.emoji} ${m.label} gifts for ${who}`,
        href: amazonSearchUrl(`${m.label} gifts for ${who}${budgetSuffix}`),
      };
    });
  }, [answers]);

  return (
    <div className="rounded-3xl border border-line bg-surface p-6 text-center">
      <Maxi size={48} />
      <p className="mt-4 font-display text-lg font-bold text-ink">
        My catalog came up short for this one
      </p>
      <p className="mx-auto mt-1 max-w-sm text-sm text-ink-soft">
        Happens to the best consults. These searches are aimed exactly where we landed:
      </p>
      <div className="mt-4 flex flex-col gap-2">
        {links.map((l) => (
          <a
            key={l.href}
            href={l.href}
            target="_blank"
            rel={AFFILIATE_REL}
            className="rounded-xl border border-line bg-cream-2 px-4 py-3 text-sm font-semibold text-ink transition-colors hover:border-ink/25"
          >
            {l.label} →
          </a>
        ))}
      </div>
      <button onClick={onReset} className="mt-4 text-sm font-bold text-coral hover:opacity-80">
        ↺ Start the consult over
      </button>
    </div>
  );
}
