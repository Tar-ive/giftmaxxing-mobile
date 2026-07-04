"use client";

import { useEffect, useState } from "react";
import { Icons } from "@/components/ui";
import { GRADIENTS } from "@/lib/data";
import {
  type Milestone,
  type MilestoneCategory,
  type RewardMode,
  CATEGORY_META,
  REWARD_MODE_META,
  DEMO_MILESTONES,
  loadMilestones,
  saveMilestones,
  createMilestone,
  completeMilestone,
  claimReward,
  activeMilestones,
  completedMilestones,
  unclaimedRewards,
  totalRewardBudget,
  daysRemaining,
  isOverdue,
} from "@/lib/milestones";
import {
  type ImportantEvent,
  type Recipient,
  EVENT_TYPE_META,
  RELATION_META,
  upcomingEvents,
  formatEventDate,
  relationFor,
} from "@/lib/events";
import {
  type SoftConnection,
  fetchConnections,
  getMyUserId,
  isApiConfigured,
  migrateEvents,
  saveEvent,
  patchEvent,
  deleteEvent,
} from "@/lib/api";
import { loadProfile } from "@/lib/onboarding";
import { CirclesPanel } from "@/components/app/circles-panel";
import { GiftPromptCards } from "@/components/app/gift-prompt-card";
import { Maxi } from "@/components/ui";
import Link from "next/link";

type TopTab = "personal" | "shared" | "circles";

export default function EventsPage() {
  const [topTab, setTopTab] = useState<TopTab>("personal");
  const [milestones, setMilestones] = useState<Milestone[]>([]);
  const [creating, setCreating] = useState(false);
  const [milestoneTab, setMilestoneTab] = useState<"active" | "completed" | "rewards">("active");

  // Shared tab state
  const [connections, setConnections] = useState<SoftConnection[]>([]);
  const [profileEvents, setProfileEvents] = useState<{ events: ImportantEvent[]; recipients: Recipient[] }>({ events: [], recipients: [] });
  const [loadingShared, setLoadingShared] = useState(false);

  // Honor a deep-link tab (?tab=shared|personal) from the right-rail Events widget.
  useEffect(() => {
    const t = new URLSearchParams(window.location.search).get("tab");
    if (t === "shared" || t === "personal" || t === "circles") {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setTopTab(t);
    }
  }, []);

  useEffect(() => {
    const stored = loadMilestones();
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setMilestones(stored.length ? stored : DEMO_MILESTONES);

    // Mirror real (non-demo) personal milestones into the events table + graph
    // once signed in, so nothing collected is missed server-side.
    if (stored.length) {
      const uid = getMyUserId();
      if (uid && isApiConfigured()) {
        void migrateEvents(uid, stored as unknown as Record<string, unknown>[]);
      }
    }

    const profile = loadProfile();
    if (profile) {
      setProfileEvents({
        events: profile.events ?? [],
        recipients: profile.recipients ?? [],
      });
    }
  }, []);

  useEffect(() => {
    if (topTab !== "shared") return;
    const userId = getMyUserId();
    if (!userId || !isApiConfigured()) return;
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setLoadingShared(true);
    fetchConnections(userId)
      .then((res) => setConnections(res.items))
      .finally(() => setLoadingShared(false));
  }, [topTab]);

  const persist = (list: Milestone[]) => {
    setMilestones(list);
    saveMilestones(list);
  };

  const handleCreate = (ms: Milestone) => {
    persist([ms, ...milestones]);
    setCreating(false);
    setMilestoneTab("active");
    const uid = getMyUserId();
    if (uid) void saveEvent(uid, ms as unknown as Record<string, unknown>);
  };

  const handleComplete = (id: string) => {
    persist(milestones.map((m) => (m.id === id ? completeMilestone(m) : m)));
    const uid = getMyUserId();
    if (uid) void patchEvent(uid, id, { status: "completed", completedAt: Date.now() });
  };

  const handleClaim = (id: string) => {
    persist(milestones.map((m) => (m.id === id ? claimReward(m) : m)));
    const uid = getMyUserId();
    if (uid) void patchEvent(uid, id, { giftOrderedAt: Date.now() });
  };

  const handleDelete = (id: string) => {
    persist(milestones.filter((m) => m.id !== id));
    const uid = getMyUserId();
    if (uid) void deleteEvent(uid, id);
  };

  const active = activeMilestones(milestones);
  const completed = completedMilestones(milestones);
  const unclaimed = unclaimedRewards(milestones);
  const totalBudget = totalRewardBudget(milestones);

  // Shared: profile occasions + EVERY soft profile collected from challenges
  // (with or without a birthday). Birthdays first, then newest.
  const upcoming = upcomingEvents(profileEvents.events, 365);
  const softProfiles = [...connections].sort((a, b) => {
    if (!!b.birthday !== !!a.birthday) return b.birthday ? 1 : -1;
    return (b.createdAt ?? 0) - (a.createdAt ?? 0);
  });

  return (
    <div className="mx-auto max-w-3xl px-4 py-5 sm:py-8">
      <header className="mb-5 flex flex-wrap items-end justify-between gap-3 sm:mb-6">
        <div>
          <h1 className="font-display text-2xl font-extrabold text-ink sm:text-3xl">Events</h1>
          <p className="mt-1 text-ink-soft">
            Your milestones, shared dates, and family gift circles.
          </p>
        </div>
        {topTab === "personal" && (
          <button
            onClick={() => setCreating((c) => !c)}
            className="shrink-0 rounded-full bg-coral px-5 py-2.5 text-sm font-bold text-white transition-opacity hover:opacity-90"
          >
            {creating ? "Close" : "New milestone"}
          </button>
        )}
      </header>

      {/* Top-level tabs: Personal / Shared / Circles */}
      <div className="mb-5 flex gap-1 rounded-xl border border-line bg-cream p-1">
        {(["personal", "shared", "circles"] as TopTab[]).map((t) => (
          <button
            key={t}
            onClick={() => setTopTab(t)}
            className={`flex-1 rounded-lg px-3 py-2.5 text-sm font-semibold capitalize transition-colors ${
              topTab === t
                ? "bg-surface text-ink shadow-sm"
                : "text-ink-soft hover:text-ink"
            }`}
          >
            {t}
          </button>
        ))}
      </div>

      {topTab === "circles" && <CirclesPanel />}

      {topTab === "personal" && (
        <>
          {/* Gift-prompt reminders for events within their lead window */}
          <GiftPromptCards />

          {/* Reward bank summary */}
          {unclaimed.length > 0 && (
            <div className="mb-6 rounded-2xl border border-coral/20 bg-coral-soft p-4">
              <div className="flex items-center gap-3">
                <span className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-coral text-lg text-white">
                  <Icons.gift size={20} />
                </span>
                <div className="flex-1">
                  <p className="text-sm font-bold text-ink">
                    You have ${totalBudget} in unclaimed rewards!
                  </p>
                  <p className="text-xs text-ink-soft">
                    {unclaimed.length} milestone{unclaimed.length !== 1 ? "s" : ""}{" "}
                    completed — claim your gifts below.
                  </p>
                </div>
                <button
                  onClick={() => setMilestoneTab("rewards")}
                  className="rounded-full bg-coral px-4 py-2 text-xs font-bold text-white"
                >
                  Claim
                </button>
              </div>
            </div>
          )}

          {creating && <CreateMilestone onCreate={handleCreate} />}

          {/* Milestone sub-tabs */}
          <div className="mb-5 flex gap-1 rounded-xl bg-cream p-1 border border-line">
            {(["active", "completed", "rewards"] as const).map((t) => (
              <button
                key={t}
                onClick={() => setMilestoneTab(t)}
                className={`flex-1 rounded-lg px-3 py-2 text-sm font-semibold capitalize transition-colors ${
                  milestoneTab === t
                    ? "bg-surface text-ink shadow-sm"
                    : "text-ink-soft hover:text-ink"
                }`}
              >
                {t === "rewards" ? `Rewards (${unclaimed.length})` : t}
              </button>
            ))}
          </div>

          {milestoneTab === "active" && (
            <div className="space-y-4">
              {active.length === 0 && (
                <EmptyState emoji="🎯" text="No active milestones. Set a goal and earn a reward!" />
              )}
              {active.map((ms) => (
                <MilestoneCard key={ms.id} milestone={ms} onComplete={handleComplete} onDelete={handleDelete} />
              ))}
            </div>
          )}

          {milestoneTab === "completed" && (
            <div className="space-y-4">
              {completed.length === 0 && <EmptyState emoji="🏆" text="No completed milestones yet. Keep going!" />}
              {completed.map((ms) => (
                <MilestoneCard key={ms.id} milestone={ms} onClaim={handleClaim} onDelete={handleDelete} />
              ))}
            </div>
          )}

          {milestoneTab === "rewards" && (
            <div className="space-y-4">
              {unclaimed.length === 0 && (
                <EmptyState emoji="🎁" text="All rewards claimed! Complete more milestones to earn new ones." />
              )}
              {unclaimed.map((ms) => (
                <RewardCard key={ms.id} milestone={ms} onClaim={handleClaim} />
              ))}
            </div>
          )}
        </>
      )}

      {topTab === "shared" && (
        <div className="space-y-5">
          {/* Upcoming events from profile recipients */}
          {upcoming.length > 0 && (
            <section>
              <p className="mb-3 text-sm font-bold text-ink-soft">Upcoming occasions</p>
              <div className="space-y-2">
                {upcoming.map(({ event, days }) => {
                  const recipient = relationFor(event, profileEvents.recipients);
                  const meta = EVENT_TYPE_META[event.type];
                  return (
                    <div
                      key={event.id}
                      className="flex items-center gap-3 rounded-2xl border border-line bg-surface p-4"
                    >
                      <span className="grid h-12 w-12 shrink-0 place-items-center rounded-xl bg-coral-soft text-2xl">
                        {meta.emoji}
                      </span>
                      <div className="min-w-0 flex-1">
                        <p className="text-sm font-bold text-ink">
                          {recipient?.name ?? "Someone"}&apos;s {meta.label.toLowerCase()}
                        </p>
                        <p className="text-xs text-ink-soft">
                          {formatEventDate(event)}
                          {recipient && ` · ${RELATION_META[recipient.relation].label}`}
                        </p>
                      </div>
                      <span
                        className={`shrink-0 rounded-full px-3 py-1 text-xs font-bold ${
                          days <= 7
                            ? "bg-coral-soft text-coral-ink"
                            : days <= 30
                              ? "bg-amber-100 text-amber-700"
                              : "bg-ink/5 text-ink-soft"
                        }`}
                      >
                        {days === 0 ? "Today!" : days === 1 ? "Tomorrow" : `${days}d`}
                      </span>
                    </div>
                  );
                })}
              </div>
            </section>
          )}

          {/* Soft profiles from challenges (the viral loop): their swiped taste
              + a one-tap link to shop gifts personalized for them. */}
          <section>
            <p className="mb-3 text-sm font-bold text-ink-soft">
              Friends from challenges
            </p>
            {loadingShared ? (
              <div className="space-y-2">
                {Array.from({ length: 3 }).map((_, i) => (
                  <div key={i} className="h-16 animate-pulse rounded-2xl bg-line" />
                ))}
              </div>
            ) : softProfiles.length > 0 ? (
              <div className="space-y-2">
                {softProfiles.map((c) => {
                  const chips = Array.from(
                    new Set([...(c.interests ?? []), ...(c.vibes ?? [])])
                  ).slice(0, 4);
                  return (
                    <div
                      key={c.connectionId}
                      className="rounded-2xl border border-line bg-surface p-4"
                    >
                      <div className="flex items-center gap-3">
                        <span className="grid h-12 w-12 shrink-0 place-items-center rounded-xl bg-lilac/20 text-coral">
                          <Icons.gift size={22} />
                        </span>
                        <div className="min-w-0 flex-1">
                          <p className="text-sm font-bold text-ink">{c.guestName}</p>
                          <p className="text-xs text-ink-soft">
                            {c.birthday
                              ? `Birthday ${c.birthday}`
                              : "Taste saved from their swipe challenge"}
                            {c.totalSwipes ? ` · liked ${c.yesCount ?? 0}/${c.totalSwipes}` : ""}
                          </p>
                        </div>
                        <Link
                          href={`/feed/ideas?cid=${encodeURIComponent(c.connectionId)}`}
                          className="shrink-0 rounded-full bg-coral px-3 py-1.5 text-[11px] font-bold text-white transition-opacity hover:opacity-90 sm:px-4 sm:py-2 sm:text-xs"
                        >
                          Gift {c.guestName.split(/\s+/)[0]}
                        </Link>
                      </div>
                      {chips.length > 0 && (
                        <div className="mt-3 flex flex-wrap gap-1.5">
                          {chips.map((t) => (
                            <span
                              key={t}
                              className="rounded-full bg-ink/5 px-2.5 py-1 text-xs font-semibold text-ink-soft"
                            >
                              {t}
                            </span>
                          ))}
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            ) : (
              <EmptyState
                emoji="🤝"
                text={
                  isApiConfigured()
                    ? "No soft profiles yet. Send swipe challenges to friends to collect their taste!"
                    : "Soft profiles appear here once the backend is deployed and friends complete challenges."
                }
              />
            )}
          </section>

          {/* If no profile events either */}
          {upcoming.length === 0 && softProfiles.length === 0 && !loadingShared && (
            <EmptyState
              emoji="📅"
              text="No shared events yet. Add recipients in onboarding or send swipe challenges to friends!"
            />
          )}
        </div>
      )}
    </div>
  );
}

// ── Milestone Card ────────────────────────────────────────────────────────────

function MilestoneCard({
  milestone,
  onComplete,
  onClaim,
  onDelete,
}: {
  milestone: Milestone;
  onComplete?: (id: string) => void;
  onClaim?: (id: string) => void;
  onDelete?: (id: string) => void;
}) {
  const meta = CATEGORY_META[milestone.category];
  const days = daysRemaining(milestone);
  const overdue = isOverdue(milestone);
  const isActive = milestone.status === "active";
  const isCompleted = milestone.status === "completed";
  const hasClaimed = !!milestone.giftOrderedAt;

  return (
    <div className="overflow-hidden rounded-2xl border border-line bg-surface shadow-sm">
      <div className="flex gap-4 p-4">
        <div
          className="grid h-14 w-14 shrink-0 place-items-center rounded-xl text-2xl"
          style={{ background: GRADIENTS[categoryGrad(milestone.category)] }}
        >
          {meta.emoji}
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <span className="rounded-full bg-ink/5 px-2 py-0.5 text-[11px] font-bold text-ink-soft">
              {meta.label}
            </span>
            {isActive && overdue && (
              <span className="rounded-full bg-red-100 px-2 py-0.5 text-[11px] font-bold text-red-600">
                Overdue
              </span>
            )}
            {isActive && !overdue && days !== null && days <= 7 && (
              <span className="rounded-full bg-amber-100 px-2 py-0.5 text-[11px] font-bold text-amber-700">
                {days}d left
              </span>
            )}
            {isCompleted && !hasClaimed && (
              <span className="rounded-full bg-green-100 px-2 py-0.5 text-[11px] font-bold text-green-700">
                Reward ready
              </span>
            )}
            {isCompleted && hasClaimed && (
              <span className="rounded-full bg-coral-soft px-2 py-0.5 text-[11px] font-bold text-coral-ink">
                Claimed
              </span>
            )}
          </div>
          <h3 className="mt-1 font-display text-lg font-bold text-ink">
            {milestone.title}
          </h3>
          {milestone.description && (
            <p className="mt-0.5 line-clamp-2 text-sm text-ink-soft">
              {milestone.description}
            </p>
          )}
          <div className="mt-2 flex flex-wrap items-center gap-3 text-xs text-ink-faint">
            <span className="font-semibold text-ink">
              ${milestone.rewardBudget} reward
            </span>
            <span>{REWARD_MODE_META[milestone.rewardMode].emoji} {REWARD_MODE_META[milestone.rewardMode].label}</span>
            {milestone.targetDate && (
              <span>
                {isActive
                  ? days !== null
                    ? overdue
                      ? `${Math.abs(days)}d overdue`
                      : `${days}d remaining`
                    : ""
                  : `Completed ${milestone.completedAt ? new Date(milestone.completedAt).toLocaleDateString() : ""}`}
              </span>
            )}
          </div>
          {milestone.rewardNote && (
            <p className="mt-1.5 text-xs italic text-ink-soft">
              &ldquo;{milestone.rewardNote}&rdquo;
            </p>
          )}
        </div>
      </div>

      <div className="flex items-center gap-2 border-t border-line px-4 py-3">
        {isActive && onComplete && (
          <button
            onClick={() => onComplete(milestone.id)}
            className="flex items-center gap-1.5 rounded-full bg-green-600 px-4 py-2 text-xs font-bold text-white transition-opacity hover:opacity-90"
          >
            <Icons.check size={14} /> Done — I did it!
          </button>
        )}
        {isCompleted && !hasClaimed && onClaim && (
          <button
            onClick={() => onClaim(milestone.id)}
            className="flex items-center gap-1.5 rounded-full bg-coral px-4 py-2 text-xs font-bold text-white transition-opacity hover:opacity-90"
          >
            <Icons.gift size={14} /> Claim reward
          </button>
        )}
        {onDelete && (
          <button
            onClick={() => onDelete(milestone.id)}
            className="ml-auto text-xs font-medium text-ink-faint hover:text-red-500"
          >
            Remove
          </button>
        )}
      </div>
    </div>
  );
}

// ── Reward Card ───────────────────────────────────────────────────────────────

function RewardCard({
  milestone,
  onClaim,
}: {
  milestone: Milestone;
  onClaim: (id: string) => void;
}) {
  const meta = CATEGORY_META[milestone.category];
  const mode = REWARD_MODE_META[milestone.rewardMode];

  return (
    <div className="overflow-hidden rounded-2xl border-2 border-coral/30 bg-surface shadow-sm">
      <div className="bg-coral-soft p-4">
        <div className="flex items-center gap-3">
          <span className="text-2xl">{meta.emoji}</span>
          <div className="flex-1">
            <p className="text-sm font-bold text-ink">You earned this!</p>
            <p className="text-xs text-ink-soft">Completed: {milestone.title}</p>
          </div>
          <span className="font-display text-2xl font-extrabold text-coral">
            ${milestone.rewardBudget}
          </span>
        </div>
      </div>
      <div className="p-4">
        {milestone.rewardNote && (
          <p className="mb-3 text-sm text-ink-soft">
            Your reward plan: &ldquo;{milestone.rewardNote}&rdquo;
          </p>
        )}
        <div className="flex items-center gap-2 rounded-xl bg-cream p-3 border border-line">
          <Maxi size={28} />
          <p className="flex-1 text-xs text-ink-soft">
            {mode.emoji === "🎁"
              ? "Maxi is ready to pick something perfect based on your taste profile."
              : mode.emoji === "🛍️"
                ? "Browse the feed and pick something you love within your $" + milestone.rewardBudget + " budget."
                : "Maxi has suggestions ready, or browse yourself!"}
          </p>
        </div>
        <button
          onClick={() => onClaim(milestone.id)}
          className="mt-3 w-full rounded-full bg-coral py-3 text-sm font-bold text-white transition-opacity hover:opacity-90"
        >
          {milestone.rewardMode === "auto-gift"
            ? "Let Maxi pick my gift"
            : milestone.rewardMode === "self-order"
              ? "Browse gifts for myself"
              : "See Maxi's picks or browse"}
        </button>
      </div>
    </div>
  );
}

// ── Create form ───────────────────────────────────────────────────────────────

function CreateMilestone({ onCreate }: { onCreate: (ms: Milestone) => void }) {
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [category, setCategory] = useState<MilestoneCategory>("career");
  const [rewardMode, setRewardMode] = useState<RewardMode>("self-order");
  const [budget, setBudget] = useState("100");
  const [rewardNote, setRewardNote] = useState("");
  const [targetDate, setTargetDate] = useState("");

  const submit = () => {
    if (!title.trim()) return;
    const ms = createMilestone({
      title: title.trim(),
      description: description.trim() || undefined,
      category,
      rewardMode,
      rewardBudget: parseInt(budget || "0", 10) || 50,
      rewardNote: rewardNote.trim() || undefined,
      targetDate: targetDate || undefined,
    });
    onCreate(ms);
  };

  return (
    <div className="mb-6 rounded-3xl border border-line bg-surface p-5">
      <h2 className="font-bold text-ink">Set a new milestone</h2>
      <p className="mt-0.5 text-xs text-ink-soft">
        Define a goal. When you hit it, you earn a self-gift.
      </p>

      <div className="mt-4 space-y-3">
        <input
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="What's your goal? (e.g. Finish hackathon project)"
          className="w-full rounded-xl border border-line bg-cream px-4 py-2.5 text-sm text-ink outline-none focus:border-coral"
        />

        <textarea
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          rows={2}
          placeholder="Describe what success looks like…"
          className="w-full resize-none rounded-xl border border-line bg-cream px-4 py-2.5 text-sm text-ink outline-none focus:border-coral"
        />

        <div className="flex flex-col gap-3 sm:flex-row">
          <select
            value={category}
            onChange={(e) => setCategory(e.target.value as MilestoneCategory)}
            className="flex-1 rounded-xl border border-line bg-cream px-4 py-2.5 text-sm text-ink outline-none focus:border-coral"
          >
            {Object.entries(CATEGORY_META).map(([key, { label, emoji }]) => (
              <option key={key} value={key}>
                {emoji} {label}
              </option>
            ))}
          </select>

          <input
            type="date"
            value={targetDate}
            onChange={(e) => setTargetDate(e.target.value)}
            className="rounded-xl border border-line bg-cream px-4 py-2.5 text-sm text-ink outline-none focus:border-coral"
            placeholder="Deadline (optional)"
          />
        </div>

        <div className="rounded-xl border border-line bg-cream p-3">
          <p className="mb-2 text-xs font-semibold text-ink-soft">Reward budget</p>
          <div className="flex flex-wrap items-center gap-3">
            <div className="flex items-center gap-1.5 rounded-lg border border-line bg-surface px-3 py-2">
              <span className="text-sm text-ink-faint">$</span>
              <input
                value={budget}
                onChange={(e) => setBudget(e.target.value.replace(/[^0-9]/g, ""))}
                inputMode="numeric"
                className="w-20 bg-transparent text-sm font-bold text-ink outline-none"
              />
            </div>
            <div className="flex flex-wrap gap-1.5">
              {[25, 50, 100, 200].map((amt) => (
                <button
                  key={amt}
                  type="button"
                  onClick={() => setBudget(String(amt))}
                  className={`rounded-full border px-3 py-1 text-xs font-semibold transition-colors ${
                    budget === String(amt)
                      ? "border-coral bg-coral-soft text-coral-ink"
                      : "border-line text-ink-soft hover:bg-ink/5"
                  }`}
                >
                  ${amt}
                </button>
              ))}
            </div>
          </div>
        </div>

        <div className="rounded-xl border border-line bg-cream p-3">
          <p className="mb-2 text-xs font-semibold text-ink-soft">When I hit this milestone…</p>
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
            {(Object.entries(REWARD_MODE_META) as [RewardMode, typeof REWARD_MODE_META[RewardMode]][]).map(
              ([key, { label, desc, emoji }]) => (
                <button
                  key={key}
                  type="button"
                  onClick={() => setRewardMode(key)}
                  className={`rounded-xl border p-3 text-left transition-colors ${
                    rewardMode === key
                      ? "border-coral bg-coral-soft"
                      : "border-line hover:bg-ink/5"
                  }`}
                >
                  <span className="text-lg">{emoji}</span>
                  <p className="mt-1 text-xs font-bold text-ink">{label}</p>
                  <p className="mt-0.5 text-[11px] text-ink-soft">{desc}</p>
                </button>
              )
            )}
          </div>
        </div>

        <input
          value={rewardNote}
          onChange={(e) => setRewardNote(e.target.value)}
          placeholder="Reward idea (e.g. Go shopping for $100, Travel somewhere)"
          className="w-full rounded-xl border border-line bg-cream px-4 py-2.5 text-sm text-ink outline-none focus:border-coral"
        />

        <button
          onClick={submit}
          disabled={!title.trim()}
          className="w-full rounded-full bg-coral py-2.5 text-sm font-bold text-white transition-opacity hover:opacity-90 disabled:opacity-40"
        >
          Create milestone
        </button>
      </div>
    </div>
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function EmptyState({ emoji, text }: { emoji: string; text: string }) {
  return (
    <div className="flex flex-col items-center gap-2 py-16 text-center">
      <span className="text-4xl">{emoji}</span>
      <p className="text-sm text-ink-faint">{text}</p>
    </div>
  );
}

function categoryGrad(cat: MilestoneCategory) {
  const map: Record<MilestoneCategory, string> = {
    career: "sky",
    fitness: "coral",
    learning: "lilac",
    creative: "rose",
    travel: "sage",
    social: "peach",
    finance: "butter",
    wellness: "sage",
    other: "lilac",
  };
  return (map[cat] ?? "coral") as import("@/lib/data").Grad;
}
