"use client";

// The "Circles" tab on /feed/events — your family/friend gift groups.
// Create a circle, share the link into the group chat, and see every
// member's next gift moment across all your circles in one countdown.

import { useEffect, useState } from "react";
import Link from "next/link";
import {
  type MyCircle,
  type UpcomingMoment,
  createCircle,
  fetchCircle,
  loadMyCircles,
  rememberCircle,
  forgetCircle,
  upcomingMoments,
  circleShareUrl,
} from "@/lib/circles";
import { isApiConfigured } from "@/lib/api";
import { Icons } from "@/components/ui";

const CIRCLE_EMOJI = ["👨‍👩‍👧‍👦", "🏠", "🎉", "💛", "🧑‍🤝‍🧑", "🎓", "🏢", "⚽"];

export function CirclesPanel() {
  const [mine, setMine] = useState<MyCircle[]>([]);
  const [moments, setMoments] = useState<(UpcomingMoment & { circleName: string; circleId: string })[]>([]);
  const [loading, setLoading] = useState(false);
  const [creating, setCreating] = useState(false);

  useEffect(() => {
    const circles = loadMyCircles();
    // localStorage is only readable client-side — same pattern as the rest
    // of the app's local-first stores.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setMine(circles);
    if (!circles.length || !isApiConfigured()) return;
    setLoading(true);
    void Promise.all(circles.map((c) => fetchCircle(c.circleId)))
      .then((results) => {
        const all: (UpcomingMoment & { circleName: string; circleId: string })[] = [];
        results.forEach((data, i) => {
          if (!data) return;
          for (const m of upcomingMoments(data)) {
            all.push({ ...m, circleName: data.circle.name, circleId: circles[i].circleId });
          }
        });
        setMoments(all.sort((a, b) => a.days - b.days).slice(0, 12));
      })
      .finally(() => setLoading(false));
  }, []);

  const removeCircle = (circleId: string) => {
    forgetCircle(circleId);
    setMine((list) => list.filter((c) => c.circleId !== circleId));
    setMoments((list) => list.filter((m) => m.circleId !== circleId));
  };

  return (
    <div className="space-y-6">
      {/* What circles are — shown until you have one */}
      {mine.length === 0 && !creating && (
        <div className="rounded-3xl border border-line bg-surface p-6 text-center sm:p-8">
          <span className="text-4xl">👨‍👩‍👧‍👦</span>
          <h2 className="mt-3 font-display text-xl font-extrabold text-ink sm:text-2xl">
            Never miss a family gift moment
          </h2>
          <p className="mx-auto mt-2 max-w-md text-sm text-ink-soft">
            Make a circle for your family or friend group, drop the link in the
            group chat, and everyone adds their birthday. One shared calendar of
            gift moments — no app, no sign-ups for them.
          </p>
          <button
            onClick={() => setCreating(true)}
            className="mt-5 inline-flex items-center gap-2 rounded-full bg-coral px-6 py-3 text-sm font-bold text-white shadow-lg shadow-coral/30 transition-opacity hover:opacity-90"
          >
            <Icons.users size={18} /> Create your circle
          </button>
        </div>
      )}

      {mine.length > 0 && !creating && (
        <button
          onClick={() => setCreating(true)}
          className="inline-flex items-center gap-2 rounded-full bg-coral px-5 py-2.5 text-sm font-bold text-white transition-opacity hover:opacity-90"
        >
          <Icons.users size={16} /> New circle
        </button>
      )}

      {creating && <CreateCircleCard onDone={() => setCreating(false)} />}

      {/* Cross-circle countdown */}
      {(moments.length > 0 || loading) && (
        <section>
          <h3 className="mb-3 text-xs font-bold uppercase tracking-wide text-ink-faint">
            Coming up across your circles
          </h3>
          {loading && moments.length === 0 ? (
            <div className="h-20 animate-pulse rounded-2xl bg-line/50" />
          ) : (
            <div className="space-y-2">
              {moments.map((m) => (
                <Link
                  key={`${m.circleId}-${m.key}`}
                  href={`/circle/${m.circleId}`}
                  className="flex items-center gap-3 rounded-2xl border border-line bg-surface p-3 transition-colors hover:border-coral/40"
                >
                  <span className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-coral-soft text-lg">
                    {m.emoji}
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-bold text-ink">
                      {m.title}
                      {m.turning != null && (
                        <span className="font-semibold text-ink-soft"> — turning {m.turning}</span>
                      )}
                    </p>
                    <p className="text-xs text-ink-faint">{m.circleName}</p>
                  </div>
                  <span
                    className={`shrink-0 rounded-full px-3 py-1 text-xs font-bold ${
                      m.days <= 14 ? "bg-coral text-white" : "bg-cream text-ink-soft"
                    }`}
                  >
                    {m.days === 0 ? "Today!" : m.days === 1 ? "Tomorrow" : `${m.days} days`}
                  </span>
                </Link>
              ))}
            </div>
          )}
        </section>
      )}

      {/* Your circles */}
      {mine.length > 0 && (
        <section>
          <h3 className="mb-3 text-xs font-bold uppercase tracking-wide text-ink-faint">
            Your circles
          </h3>
          <div className="grid gap-3 sm:grid-cols-2">
            {mine.map((c) => (
              <div
                key={c.circleId}
                className="flex items-center gap-3 rounded-2xl border border-line bg-surface p-4"
              >
                <span className="text-2xl">{c.emoji ?? "🎁"}</span>
                <div className="min-w-0 flex-1">
                  <Link
                    href={`/circle/${c.circleId}`}
                    className="block truncate text-sm font-bold text-ink hover:text-coral"
                  >
                    {c.name}
                  </Link>
                  {c.joinedAs && (
                    <p className="text-xs text-ink-faint">you&apos;re {c.joinedAs}</p>
                  )}
                </div>
                <Link
                  href={`/circle/${c.circleId}`}
                  className="shrink-0 rounded-full bg-cream px-3.5 py-1.5 text-xs font-bold text-ink transition-colors hover:bg-coral-soft"
                >
                  Open
                </Link>
                <button
                  onClick={() => removeCircle(c.circleId)}
                  aria-label={`Leave ${c.name}`}
                  className="shrink-0 text-ink-faint transition-colors hover:text-ink"
                >
                  <Icons.close size={16} />
                </button>
              </div>
            ))}
          </div>
        </section>
      )}
    </div>
  );
}

function CreateCircleCard({ onDone }: { onDone: () => void }) {
  const [name, setName] = useState("");
  const [emoji, setEmoji] = useState(CIRCLE_EMOJI[0]);
  const [yourName, setYourName] = useState("");
  const [birthday, setBirthday] = useState("");
  const [busy, setBusy] = useState(false);
  const [created, setCreated] = useState<{ circleId: string; url: string } | null>(null);
  const [copied, setCopied] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async () => {
    const trimmed = name.trim();
    if (!trimmed || busy) return;
    setBusy(true);
    setError(null);
    const circleId = await createCircle({
      name: trimmed,
      emoji,
      creator: yourName.trim()
        ? { name: yourName.trim(), birthday: birthday || undefined }
        : undefined,
    });
    setBusy(false);
    if (!circleId) {
      setError("Couldn't create the circle — try again in a moment.");
      return;
    }
    rememberCircle({ circleId, name: trimmed, emoji, joinedAs: yourName.trim() || null });
    setCreated({ circleId, url: circleShareUrl(circleId) });
  };

  const share = async () => {
    if (!created) return;
    const text = `Join our "${name.trim()}" gift circle — add your birthday so nobody misses it 🎁 ${created.url}`;
    if (navigator.share) {
      try {
        await navigator.share({ text });
        return;
      } catch {
        // fall through to clipboard
      }
    }
    await navigator.clipboard.writeText(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  if (created) {
    return (
      <div className="rounded-3xl border border-coral/30 bg-coral-soft/60 p-6 text-center">
        <span className="text-3xl">{emoji}</span>
        <h3 className="mt-2 font-display text-lg font-extrabold text-ink">
          {name.trim()} is live!
        </h3>
        <p className="mx-auto mt-1 max-w-sm text-sm text-ink-soft">
          Drop the link in the group chat — everyone who opens it can add their
          name and birthday.
        </p>
        <div className="mt-4 flex flex-col items-center gap-2 sm:flex-row sm:justify-center">
          <button
            onClick={share}
            className="inline-flex w-full items-center justify-center gap-2 rounded-full bg-coral px-6 py-3 text-sm font-bold text-white shadow-lg shadow-coral/30 transition-opacity hover:opacity-90 sm:w-auto"
          >
            <Icons.share size={16} /> {copied ? "Link copied!" : "Share the invite"}
          </button>
          <Link
            href={`/circle/${created.circleId}`}
            className="inline-flex w-full items-center justify-center rounded-full bg-surface px-6 py-3 text-sm font-bold text-ink transition-colors hover:bg-cream sm:w-auto"
          >
            Open the circle
          </Link>
        </div>
      </div>
    );
  }

  return (
    <div className="rounded-3xl border border-line bg-surface p-5 sm:p-6">
      <h3 className="font-display text-lg font-extrabold text-ink">New circle</h3>
      <p className="mt-1 text-sm text-ink-soft">
        Name it after the group — family, roommates, work friends…
      </p>

      <div className="mt-4 space-y-3">
        <input
          type="text"
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder='Circle name (e.g. "The Sharma Family")'
          maxLength={60}
          className="w-full rounded-xl border border-line bg-cream px-4 py-3 text-sm font-medium text-ink outline-none focus:border-coral focus:ring-2 focus:ring-coral/20"
        />
        <div className="flex flex-wrap gap-2">
          {CIRCLE_EMOJI.map((e) => (
            <button
              key={e}
              onClick={() => setEmoji(e)}
              aria-pressed={emoji === e}
              className={`grid h-10 w-10 place-items-center rounded-full text-lg transition-colors ${
                emoji === e ? "bg-coral-soft ring-2 ring-coral" : "bg-cream hover:bg-coral-soft/50"
              }`}
            >
              {e}
            </button>
          ))}
        </div>
        <div className="grid gap-3 sm:grid-cols-2">
          <input
            type="text"
            value={yourName}
            onChange={(e) => setYourName(e.target.value)}
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
      </div>

      {error && <p className="mt-3 text-sm font-semibold text-coral">{error}</p>}

      <div className="mt-4 flex gap-2">
        <button
          onClick={submit}
          disabled={busy || !name.trim()}
          className="flex-1 rounded-full bg-coral px-6 py-3 text-sm font-bold text-white shadow-lg shadow-coral/30 transition-opacity hover:opacity-90 disabled:opacity-40"
        >
          {busy ? "Creating…" : "Create circle"}
        </button>
        <button
          onClick={onDone}
          className="rounded-full px-5 py-3 text-sm font-semibold text-ink-soft hover:text-ink"
        >
          Cancel
        </button>
      </div>
    </div>
  );
}
