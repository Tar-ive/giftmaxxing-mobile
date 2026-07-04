"use client";

// /gift — the Gift Concierge.
//
// The product thesis, as a page: a friend who's good at gifts doesn't show you
// an infinite feed — they ask a few sharp questions about the PERSON, then say
// "get them this." This is that consult as a conversation, ending in a short
// list where every item passes the move test ("if they moved tomorrow, does it
// make it into the box?"). Public route: no account needed, built to be the
// link you send when someone texts "help, what do I get my mom".

import { useCallback, useMemo, useState } from "react";
import Link from "next/link";
import { ChatFlow, type ChatAnswers, type ChatStep } from "@/components/app/chat-flow";
import { Maxi, Icons } from "@/components/ui";
import { GRADIENTS } from "@/lib/data";
import { fetchFeed, isApiConfigured } from "@/lib/api";
import { hiResImage } from "@/lib/images";
import { outboundAffiliateUrl, amazonSearchUrl, AFFILIATE_REL } from "@/lib/affiliate";
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
  parseBudgetText,
  rankGifts,
} from "@/lib/consult";

// ── The consult script (see lib/consult.ts for the metadata) ─────────────────

const BUDGET_CHIPS = [25, 50, 100, 250].map((n) => ({ value: String(n), label: `Under $${n}` }));

function firstName(a: ChatAnswers): string | null {
  const n = typeof a.name === "string" ? a.name.trim().split(/\s+/)[0] : "";
  return n ? n.charAt(0).toUpperCase() + n.slice(1) : null;
}
const they = (a: ChatAnswers) => firstName(a) ?? "they";
const them = (a: ChatAnswers) => firstName(a) ?? "them";

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
    prompts: () => ["What's the budget? Tap one or type it — \"around $80\" works."],
    input: "chips",
    allowText: true,
    options: BUDGET_CHIPS,
    placeholder: "e.g. around $80",
    parseText: (t) => {
      const n = parseBudgetText(t);
      return n ? { value: String(n), label: `About $${n}` } : null;
    },
    rejectText: "Give me a number — \"$60\" or \"around 100\" both work.",
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

const INTRO = [
  "Hey — I'm Maxi. I find gifts people actually keep.",
  "My bar is simple: if they moved tomorrow, would this make it into the box? 📦",
  "A few quick questions about your person and I'll pull real options.",
];

// ── Page ─────────────────────────────────────────────────────────────────────

type Phase = "chat" | "thinking" | "results";

export default function GiftConciergePage() {
  const [phase, setPhase] = useState<Phase>("chat");
  const [answers, setAnswers] = useState<ConsultAnswers | null>(null);
  const [gifts, setGifts] = useState<RankedGift[]>([]);
  const [pool, setPool] = useState<Post[]>([]);
  const [flowKey, setFlowKey] = useState(0); // remount ChatFlow on "start over"

  const runConsult = useCallback(async (a: ConsultAnswers) => {
    setAnswers(a);
    setPhase("thinking");
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
  }, []);

  const onComplete = useCallback(
    (raw: ChatAnswers) => {
      const a: ConsultAnswers = {
        relation: (raw.relation as ConsultRelation) ?? "other",
        name: typeof raw.name === "string" ? raw.name : undefined,
        occasion: typeof raw.occasion === "string" ? raw.occasion : "any",
        budget: Number(raw.budget) || 50,
        worlds: Array.isArray(raw.worlds) ? (raw.worlds as WorldKey[]) : [],
        sunday: typeof raw.sunday === "string" ? raw.sunday : undefined,
        keeper: (raw.keeper as KeeperKey) ?? "light",
      };
      void runConsult(a);
    },
    [runConsult],
  );

  const rebudget = useCallback(
    (budget: number) => {
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

      {phase === "chat" && (
        <div className="min-h-0 flex-1">
          <ChatFlow key={flowKey} steps={STEPS} intro={INTRO} onComplete={onComplete} />
        </div>
      )}

      {phase === "thinking" && answers && <Thinking answers={answers} />}

      {phase === "results" && answers && (
        <Results answers={answers} gifts={gifts} onReset={reset} onRebudget={rebudget} />
      )}
    </div>
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
        Okay — {who}, {worlds || "their world"}, ${answers.budget} to spend.
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
  onRebudget: (n: number) => void;
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
      return {
        label: `${m.emoji} ${m.label} gifts for ${who}`,
        href: amazonSearchUrl(`${m.label} gifts for ${who} under $${answers.budget}`),
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
