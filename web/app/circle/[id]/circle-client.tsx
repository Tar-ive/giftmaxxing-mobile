"use client";

// The circle page itself — opened from the group-chat link. Three jobs:
//   1. Get a new arrival to add their name + birthday in under 15 seconds.
//   2. Show the group's next gift moments as a countdown, not a list of rows.
//   3. Hand the "someone's birthday is coming" moment off to gift-finding.
// Everything works signed-out; this browser remembers who you joined as.

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import {
  type CircleData,
  type UpcomingMoment,
  fetchCircle,
  joinCircle,
  addCircleEvent,
  deleteCircleEvent,
  loadMyCircles,
  rememberCircle,
  upcomingMoments,
  circleShareUrl,
} from "@/lib/circles";
import { Icons, Maxi } from "@/components/ui";

const AVATAR_GRADIENTS = [
  "linear-gradient(135deg,#FFD9C7,#FFB199)",
  "linear-gradient(135deg,#FFD3E0,#FFA8C5)",
  "linear-gradient(135deg,#FFF3C4,#FFE083)",
  "linear-gradient(135deg,#E6DBFF,#C9B3FF)",
  "linear-gradient(135deg,#CDEBFF,#9ED5FF)",
  "linear-gradient(135deg,#D6F5DC,#A8E6B5)",
];

function gradFor(name: string): string {
  let h = 0;
  for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) | 0;
  return AVATAR_GRADIENTS[Math.abs(h) % AVATAR_GRADIENTS.length];
}

function initials(name: string): string {
  return name
    .split(/\s+/)
    .slice(0, 2)
    .map((w) => w[0]?.toUpperCase() ?? "")
    .join("");
}

const OCCASION_TYPES = [
  { id: "anniversary", label: "💝 Anniversary" },
  { id: "wedding", label: "💒 Wedding" },
  { id: "graduation", label: "🎓 Graduation" },
  { id: "holiday", label: "🎄 Holiday" },
  { id: "baby-shower", label: "🍼 Baby shower" },
  { id: "occasion", label: "✨ Something else" },
];

export function CircleClient({ circleId }: { circleId: string }) {
  const [data, setData] = useState<CircleData | null>(null);
  const [state, setState] = useState<"loading" | "ready" | "missing">("loading");
  const [joinedAs, setJoinedAs] = useState<string | null>(null);
  const [showJoin, setShowJoin] = useState(false);
  const [showOccasion, setShowOccasion] = useState(false);
  const [copied, setCopied] = useState(false);

  const refresh = useCallback(async () => {
    const res = await fetchCircle(circleId);
    if (res) {
      setData(res);
      setState("ready");
    } else {
      setState((s) => (s === "ready" ? s : "missing"));
    }
  }, [circleId]);

  useEffect(() => {
    const mine = loadMyCircles().find((c) => c.circleId === circleId);
    // localStorage is only readable client-side — same pattern as the rest
    // of the app's local-first stores.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setJoinedAs(mine?.joinedAs ?? null);
    setShowJoin(!mine?.joinedAs);
    void refresh();
  }, [circleId, refresh]);

  const moments = useMemo(() => (data ? upcomingMoments(data) : []), [data]);
  const next = moments[0];

  const share = async () => {
    if (!data) return;
    const url = circleShareUrl(circleId);
    const text = `Join our "${data.circle.name}" gift circle — add your birthday so nobody misses it 🎁 ${url}`;
    if (navigator.share) {
      try {
        await navigator.share({ text });
        return;
      } catch {
        // fall through
      }
    }
    await navigator.clipboard.writeText(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  if (state === "loading") {
    return (
      <div className="flex min-h-screen items-center justify-center bg-cream">
        <div className="text-center">
          <Maxi size={56} />
          <p className="mt-3 text-sm text-ink-soft">Opening the circle…</p>
        </div>
      </div>
    );
  }

  if (state === "missing" || !data) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center bg-cream px-4 text-center">
        <Maxi size={64} />
        <h1 className="mt-5 font-display text-2xl font-extrabold text-ink">
          This circle doesn&apos;t exist (anymore)
        </h1>
        <p className="mt-2 max-w-sm text-sm text-ink-soft">
          Double-check the link, or ask whoever shared it to send a fresh one.
        </p>
        <Link
          href="/feed/events"
          className="mt-6 rounded-full bg-ink px-6 py-3 text-sm font-bold text-cream transition-opacity hover:opacity-90"
        >
          Make your own circle
        </Link>
      </div>
    );
  }

  const { circle, members, events } = data;

  return (
    <div className="min-h-screen bg-cream">
      <div className="mx-auto max-w-2xl px-4 py-8 sm:py-12">
        {/* Header */}
        <header className="text-center">
          <span className="text-5xl">{circle.emoji ?? "🎁"}</span>
          <h1 className="mt-3 font-display text-3xl font-extrabold leading-tight text-ink sm:text-4xl">
            {circle.name}
          </h1>
          <p className="mt-1.5 text-sm text-ink-soft">
            {members.length} {members.length === 1 ? "member" : "members"} · a shared
            calendar of gift moments
          </p>
          <div className="mt-4 flex flex-wrap justify-center gap-2">
            <button
              onClick={share}
              className="inline-flex items-center gap-2 rounded-full bg-coral px-5 py-2.5 text-sm font-bold text-white shadow-lg shadow-coral/30 transition-opacity hover:opacity-90"
            >
              <Icons.share size={16} /> {copied ? "Link copied!" : "Invite the group"}
            </button>
            {joinedAs && (
              <button
                onClick={() => setShowJoin((v) => !v)}
                className="rounded-full bg-surface px-5 py-2.5 text-sm font-bold text-ink transition-colors hover:bg-coral-soft"
              >
                Edit my birthday
              </button>
            )}
          </div>
        </header>

        {/* Join card — the 15-second ask for new arrivals */}
        {showJoin && (
          <JoinCard
            circleId={circleId}
            circleName={circle.name}
            circleEmoji={circle.emoji}
            defaultName={joinedAs ?? ""}
            onJoined={(name) => {
              setJoinedAs(name);
              setShowJoin(false);
              void refresh();
            }}
          />
        )}

        {/* Next moment hero */}
        {next && (
          <section className="mt-8 rounded-3xl border border-coral/25 bg-coral-soft/60 p-6 text-center">
            <p className="text-xs font-bold uppercase tracking-wide text-coral">Up next</p>
            <p className="mt-2 text-4xl">{next.emoji}</p>
            <h2 className="mt-1 font-display text-2xl font-extrabold text-ink">
              {next.title}
            </h2>
            <p className="mt-1 text-sm font-semibold text-ink-soft">
              {next.days === 0
                ? "It's today! 🎉"
                : next.days === 1
                  ? "Tomorrow!"
                  : `In ${next.days} days`}
              {next.turning != null && ` — turning ${next.turning}`}
            </p>
            <Link
              href="/feed"
              className="mt-4 inline-flex items-center gap-2 rounded-full bg-ink px-6 py-3 text-sm font-bold text-cream transition-transform hover:-translate-y-0.5"
            >
              <Icons.gift size={16} /> Find {next.who ? `${next.who} a gift` : "a gift"}
            </Link>
          </section>
        )}

        {/* Countdown list */}
        {moments.length > 1 && (
          <section className="mt-8">
            <h3 className="mb-3 text-xs font-bold uppercase tracking-wide text-ink-faint">
              Coming up
            </h3>
            <div className="space-y-2">
              {moments.slice(1).map((m) => (
                <MomentRow key={m.key} moment={m} />
              ))}
            </div>
          </section>
        )}

        {/* Members */}
        <section className="mt-8">
          <div className="mb-3 flex items-center justify-between">
            <h3 className="text-xs font-bold uppercase tracking-wide text-ink-faint">
              Who&apos;s in
            </h3>
            <button
              onClick={share}
              className="text-xs font-bold text-coral hover:underline"
            >
              + invite more
            </button>
          </div>
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
            {members.map((m) => (
              <div
                key={m.memberId}
                className="flex items-center gap-3 rounded-2xl border border-line bg-surface p-3"
              >
                <span
                  className="grid h-10 w-10 shrink-0 place-items-center rounded-full text-sm font-extrabold text-ink"
                  style={{ background: gradFor(m.name) }}
                >
                  {initials(m.name)}
                </span>
                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm font-bold text-ink">
                    {m.name}
                    {joinedAs && m.name.toLowerCase() === joinedAs.toLowerCase() && (
                      <span className="text-ink-faint"> (you)</span>
                    )}
                  </p>
                  <p className="text-xs text-ink-faint">
                    {m.birthday
                      ? `🎂 ${formatBirthday(m.birthday)}`
                      : "no birthday yet"}
                  </p>
                </div>
              </div>
            ))}
          </div>
        </section>

        {/* Shared occasions */}
        <section className="mt-8">
          <div className="mb-3 flex items-center justify-between">
            <h3 className="text-xs font-bold uppercase tracking-wide text-ink-faint">
              Other occasions
            </h3>
            <button
              onClick={() => setShowOccasion((v) => !v)}
              className="text-xs font-bold text-coral hover:underline"
            >
              {showOccasion ? "close" : "+ add one"}
            </button>
          </div>
          {showOccasion && (
            <OccasionForm
              circleId={circleId}
              addedBy={joinedAs}
              onAdded={() => {
                setShowOccasion(false);
                void refresh();
              }}
            />
          )}
          {events.length === 0 && !showOccasion && (
            <p className="rounded-2xl border border-dashed border-line bg-surface/60 p-4 text-center text-sm text-ink-soft">
              Anniversaries, graduations, the holidays you exchange gifts on —
              add them so the whole circle sees them coming.
            </p>
          )}
          {events.length > 0 && (
            <div className="space-y-2">
              {events.map((ev) => (
                <div
                  key={ev.eventId}
                  className="flex items-center gap-3 rounded-2xl border border-line bg-surface p-3"
                >
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-bold text-ink">{ev.title}</p>
                    <p className="text-xs text-ink-faint">
                      {formatBirthday(ev.date)}
                      {ev.addedBy ? ` · added by ${ev.addedBy}` : ""}
                    </p>
                  </div>
                  <button
                    onClick={() => {
                      void deleteCircleEvent(circleId, ev.eventId).then(() => refresh());
                    }}
                    aria-label={`Remove ${ev.title}`}
                    className="shrink-0 text-ink-faint transition-colors hover:text-ink"
                  >
                    <Icons.close size={15} />
                  </button>
                </div>
              ))}
            </div>
          )}
        </section>

        {/* Footer */}
        <footer className="mt-10 border-t border-line pt-6 text-center">
          <p className="text-sm text-ink-soft">
            Gift ideas for everyone in the circle, matched to their taste —
          </p>
          <Link
            href="/feed"
            className="mt-3 inline-flex items-center gap-2 rounded-full bg-surface px-6 py-3 text-sm font-bold text-ink ring-1 ring-line transition-colors hover:bg-coral-soft"
          >
            <Maxi size={22} /> Explore Giftmaxxing
          </Link>
        </footer>
      </div>
    </div>
  );
}

function MomentRow({ moment }: { moment: UpcomingMoment }) {
  return (
    <div className="flex items-center gap-3 rounded-2xl border border-line bg-surface p-3">
      <span className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-coral-soft text-lg">
        {moment.emoji}
      </span>
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-bold text-ink">
          {moment.title}
          {moment.turning != null && (
            <span className="font-semibold text-ink-soft"> — turning {moment.turning}</span>
          )}
        </p>
        <p className="text-xs text-ink-faint">
          {moment.date.toLocaleDateString(undefined, { month: "long", day: "numeric" })}
        </p>
      </div>
      <span
        className={`shrink-0 rounded-full px-3 py-1 text-xs font-bold ${
          moment.days <= 14 ? "bg-coral text-white" : "bg-cream text-ink-soft"
        }`}
      >
        {moment.days === 0 ? "Today!" : moment.days === 1 ? "Tomorrow" : `${moment.days}d`}
      </span>
    </div>
  );
}

function JoinCard({
  circleId,
  circleName,
  circleEmoji,
  defaultName,
  onJoined,
}: {
  circleId: string;
  circleName: string;
  circleEmoji: string | null;
  defaultName: string;
  onJoined: (name: string) => void;
}) {
  const [name, setName] = useState(defaultName);
  const [birthday, setBirthday] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async () => {
    const trimmed = name.trim();
    if (!trimmed || busy) return;
    setBusy(true);
    setError(null);
    const ok = await joinCircle(circleId, {
      name: trimmed,
      birthday: birthday || undefined,
    });
    setBusy(false);
    if (!ok) {
      setError("Couldn't join right now — try again in a moment.");
      return;
    }
    rememberCircle({
      circleId,
      name: circleName,
      emoji: circleEmoji,
      joinedAs: trimmed,
    });
    onJoined(trimmed);
  };

  return (
    <section className="mt-6 rounded-3xl border border-line bg-surface p-5 shadow-lg sm:p-6">
      <h2 className="font-display text-lg font-extrabold text-ink">
        {defaultName ? "Update your details" : "Add yourself to the circle"}
      </h2>
      <p className="mt-1 text-sm text-ink-soft">
        Your name and birthday — that&apos;s it. No account needed.
      </p>
      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        <input
          type="text"
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="Your name"
          maxLength={40}
          className="w-full rounded-xl border border-line bg-cream px-4 py-3 text-sm font-medium text-ink outline-none focus:border-coral focus:ring-2 focus:ring-coral/20"
        />
        <input
          type="date"
          value={birthday}
          onChange={(e) => setBirthday(e.target.value)}
          aria-label="Your birthday"
          className="w-full rounded-xl border border-line bg-cream px-4 py-3 text-sm font-medium text-ink outline-none focus:border-coral focus:ring-2 focus:ring-coral/20"
        />
      </div>
      <p className="mt-2 text-[11px] text-ink-faint">
        The year is only used for the &quot;turning N&quot; countdown — pick Jan 1
        of any year if you&apos;d rather not share it.
      </p>
      {error && <p className="mt-2 text-sm font-semibold text-coral">{error}</p>}
      <button
        onClick={submit}
        disabled={busy || !name.trim()}
        className="mt-4 w-full rounded-full bg-coral px-6 py-3 text-sm font-bold text-white shadow-lg shadow-coral/30 transition-opacity hover:opacity-90 disabled:opacity-40"
      >
        {busy ? "Joining…" : "I'm in 🎁"}
      </button>
    </section>
  );
}

function OccasionForm({
  circleId,
  addedBy,
  onAdded,
}: {
  circleId: string;
  addedBy: string | null;
  onAdded: () => void;
}) {
  const [title, setTitle] = useState("");
  const [date, setDate] = useState("");
  const [type, setType] = useState(OCCASION_TYPES[0].id);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async () => {
    if (!title.trim() || !date || busy) return;
    setBusy(true);
    setError(null);
    const ok = await addCircleEvent(circleId, {
      title: title.trim(),
      date,
      type,
      addedBy: addedBy ?? undefined,
    });
    setBusy(false);
    if (!ok) {
      setError("Couldn't save it — try again in a moment.");
      return;
    }
    onAdded();
  };

  return (
    <div className="mb-3 rounded-2xl border border-line bg-surface p-4">
      <div className="grid gap-3 sm:grid-cols-2">
        <input
          type="text"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="Title (e.g. Parents' anniversary)"
          maxLength={80}
          className="w-full rounded-xl border border-line bg-cream px-4 py-3 text-sm font-medium text-ink outline-none focus:border-coral focus:ring-2 focus:ring-coral/20 sm:col-span-2"
        />
        <input
          type="date"
          value={date}
          onChange={(e) => setDate(e.target.value)}
          aria-label="Date"
          className="w-full rounded-xl border border-line bg-cream px-4 py-3 text-sm font-medium text-ink outline-none focus:border-coral focus:ring-2 focus:ring-coral/20"
        />
        <select
          value={type}
          onChange={(e) => setType(e.target.value)}
          className="w-full rounded-xl border border-line bg-cream px-4 py-3 text-sm font-medium text-ink outline-none focus:border-coral"
        >
          {OCCASION_TYPES.map((t) => (
            <option key={t.id} value={t.id}>
              {t.label}
            </option>
          ))}
        </select>
      </div>
      {error && <p className="mt-2 text-sm font-semibold text-coral">{error}</p>}
      <button
        onClick={submit}
        disabled={busy || !title.trim() || !date}
        className="mt-3 w-full rounded-full bg-coral px-6 py-2.5 text-sm font-bold text-white transition-opacity hover:opacity-90 disabled:opacity-40"
      >
        {busy ? "Saving…" : "Add to the circle"}
      </button>
    </div>
  );
}

function formatBirthday(dateStr: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateStr);
  if (!m) return dateStr;
  const d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  return d.toLocaleDateString(undefined, { month: "long", day: "numeric" });
}
