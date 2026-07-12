"use client";

import { useCallback, useEffect, useMemo, useState, type ReactNode } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Avatar, Icons } from "@/components/ui";
import { useCurrentUser } from "@/lib/identity";
import { getMyUserId } from "@/lib/api";
import {
  FRIENDS_EVENT,
  acceptFriend,
  listFriends,
  openDm,
  removeFriend,
  requestFriend,
  searchPeople,
  type Friendship,
  type PublicPerson,
} from "@/lib/friends";
import { INTEREST_META, type InterestTag } from "@/lib/onboarding";
import { USERS } from "@/lib/social";

type Tab = "friends" | "requests" | "discover";

function gradFor(id: string): "coral" | "rose" | "lilac" | "sky" | "butter" | "sage" | "peach" {
  return (USERS[id]?.grad as "coral") ?? "coral";
}

function interestLabel(tag: string): string {
  return INTEREST_META[tag as InterestTag]?.label ?? tag;
}

function interestEmoji(tag: string): string {
  return INTEREST_META[tag as InterestTag]?.emoji ?? "✨";
}

export default function FriendsPage() {
  const me = useCurrentUser();
  const router = useRouter();
  const [tab, setTab] = useState<Tab>("friends");
  const [friends, setFriends] = useState<Friendship[]>([]);
  const [pending, setPending] = useState<Friendship[]>([]);
  const [discover, setDiscover] = useState<PublicPerson[]>([]);
  const [q, setQ] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const userId = getMyUserId() ?? "you";

  const refresh = useCallback(async () => {
    const [f, p, d] = await Promise.all([
      listFriends(userId, "accepted"),
      listFriends(userId, "pending"),
      searchPeople(q, 24),
    ]);
    setFriends(f);
    setPending(p);
    setDiscover(d.filter((ppl) => ppl.userId !== userId));
  }, [userId, q]);

  useEffect(() => {
    // Async load from API / localStorage — same pattern as other feed pages.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void refresh();
    const on = () => void refresh();
    window.addEventListener(FRIENDS_EVENT, on);
    return () => window.removeEventListener(FRIENDS_EVENT, on);
  }, [refresh]);

  const incoming = useMemo(
    () => pending.filter((f) => f.incoming || f.requestedBy !== userId),
    [pending, userId]
  );
  const outgoing = useMemo(
    () => pending.filter((f) => !f.incoming && f.requestedBy === userId),
    [pending, userId]
  );

  const friendIds = useMemo(() => new Set(friends.map((f) => f.friendId)), [friends]);
  const pendingIds = useMemo(() => new Set(pending.map((f) => f.friendId)), [pending]);

  async function onRequest(person: PublicPerson) {
    setBusy(person.userId);
    await requestFriend({
      fromUserId: userId,
      toUserId: person.userId,
      toName: person.name,
      toHandle: person.handle,
    });
    await refresh();
    setBusy(null);
  }

  async function onAccept(fromUserId: string) {
    setBusy(fromUserId);
    await acceptFriend({ userId, fromUserId });
    await refresh();
    setBusy(null);
  }

  async function onRemove(friendId: string) {
    setBusy(friendId);
    await removeFriend({ userId, friendId });
    await refresh();
    setBusy(null);
  }

  async function onMessage(friendId: string) {
    setBusy(friendId);
    const tid = await openDm({ userId, otherUserId: friendId });
    setBusy(null);
    if (tid) router.push(`/feed/messages?dm=${encodeURIComponent(tid)}`);
  }

  const TABS: { id: Tab; label: string; count?: number }[] = [
    { id: "friends", label: "Friends", count: friends.length },
    { id: "requests", label: "Requests", count: incoming.length },
    { id: "discover", label: "Discover" },
  ];

  return (
    <div className="mx-auto max-w-xl px-4 py-6">
      <header className="mb-5">
        <h1 className="font-display text-2xl font-extrabold text-ink">Friends</h1>
        <p className="mt-1 text-sm text-ink-soft">
          Connect with people on Giftmaxxing — message them, gift them, and
          find each other in your circles.
        </p>
      </header>

      <div className="mb-4 flex gap-1 rounded-xl border border-line bg-cream p-1">
        {TABS.map((t) => (
          <button
            key={t.id}
            onClick={() => setTab(t.id)}
            className={`flex-1 rounded-lg px-3 py-2 text-sm font-semibold transition-colors ${
              tab === t.id ? "bg-surface text-ink shadow-sm" : "text-ink-soft hover:text-ink"
            }`}
          >
            {t.label}
            {typeof t.count === "number" && t.count > 0 ? (
              <span className="ml-1 text-xs text-coral">({t.count})</span>
            ) : null}
          </button>
        ))}
      </div>

      {tab === "discover" && (
        <div className="mb-4 flex items-center gap-2 rounded-full border border-line bg-surface px-4 py-2.5">
          <Icons.search size={18} className="shrink-0 text-ink-faint" />
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Search people by name or handle…"
            className="min-w-0 flex-1 bg-transparent text-sm text-ink placeholder:text-ink-faint outline-none"
          />
        </div>
      )}

      {tab === "friends" && (
        <section className="space-y-1">
          {friends.length === 0 ? (
            <Empty
              title="No friends yet"
              body="Discover people who have the app, or connect inside a shared circle."
              cta={{ label: "Discover people", onClick: () => setTab("discover") }}
            />
          ) : (
            friends.map((f) => (
              <PersonRow
                key={f.friendId}
                name={f.name ?? f.friendId}
                handle={f.handle}
                interests={f.interests}
                grad={gradFor(f.friendId)}
                actions={
                  <>
                    <button
                      disabled={busy === f.friendId}
                      onClick={() => void onMessage(f.friendId)}
                      className="rounded-full bg-ink px-3 py-1.5 text-xs font-bold text-cream"
                    >
                      Message
                    </button>
                    <Link
                      href={`/feed?giftFor=${encodeURIComponent(f.friendId)}`}
                      className="rounded-full bg-coral px-3 py-1.5 text-xs font-bold text-white"
                    >
                      Gift
                    </Link>
                    <button
                      disabled={busy === f.friendId}
                      onClick={() => void onRemove(f.friendId)}
                      className="rounded-full px-2 py-1.5 text-xs font-semibold text-ink-faint hover:text-ink"
                    >
                      Remove
                    </button>
                  </>
                }
              />
            ))
          )}
        </section>
      )}

      {tab === "requests" && (
        <section className="space-y-5">
          <div>
            <h2 className="mb-2 text-xs font-bold uppercase tracking-wide text-ink-faint">
              Incoming
            </h2>
            {incoming.length === 0 ? (
              <p className="text-sm text-ink-soft">No pending requests.</p>
            ) : (
              <div className="space-y-1">
                {incoming.map((f) => (
                  <PersonRow
                    key={f.friendId}
                    name={f.name ?? f.friendId}
                    handle={f.handle}
                    grad={gradFor(f.friendId)}
                    actions={
                      <>
                        <button
                          disabled={busy === f.friendId}
                          onClick={() => void onAccept(f.friendId)}
                          className="rounded-full bg-coral px-3 py-1.5 text-xs font-bold text-white"
                        >
                          Accept
                        </button>
                        <button
                          disabled={busy === f.friendId}
                          onClick={() => void onRemove(f.friendId)}
                          className="rounded-full bg-ink/5 px-3 py-1.5 text-xs font-bold text-ink"
                        >
                          Decline
                        </button>
                      </>
                    }
                  />
                ))}
              </div>
            )}
          </div>
          {outgoing.length > 0 && (
            <div>
              <h2 className="mb-2 text-xs font-bold uppercase tracking-wide text-ink-faint">
                Sent
              </h2>
              <div className="space-y-1">
                {outgoing.map((f) => (
                  <PersonRow
                    key={f.friendId}
                    name={f.name ?? f.friendId}
                    handle={f.handle}
                    grad={gradFor(f.friendId)}
                    actions={
                      <span className="text-xs font-semibold text-ink-faint">Pending</span>
                    }
                  />
                ))}
              </div>
            </div>
          )}
        </section>
      )}

      {tab === "discover" && (
        <section className="space-y-1">
          <p className="mb-2 px-1 text-sm font-bold text-ink-soft">
            {q ? "Results" : "People on Giftmaxxing"}
          </p>
          {discover.length === 0 ? (
            <Empty
              title="Nobody matched"
              body="Try another name, or finish your own taste profile so friends can find you."
              cta={{ label: "Edit my taste", href: "/onboarding" }}
            />
          ) : (
            discover.map((p) => {
              const isFriend = friendIds.has(p.userId);
              const isPending = pendingIds.has(p.userId);
              return (
                <PersonRow
                  key={p.userId}
                  name={p.name}
                  handle={p.handle}
                  bio={p.bio}
                  interests={p.interests}
                  grad={gradFor(p.userId)}
                  href={`/feed/${p.userId}`}
                  actions={
                    isFriend ? (
                      <button
                        onClick={() => void onMessage(p.userId)}
                        className="rounded-full bg-ink px-3 py-1.5 text-xs font-bold text-cream"
                      >
                        Message
                      </button>
                    ) : isPending ? (
                      <span className="text-xs font-semibold text-ink-faint">Requested</span>
                    ) : (
                      <button
                        disabled={busy === p.userId}
                        onClick={() => void onRequest(p)}
                        className="rounded-full bg-coral px-3 py-1.5 text-xs font-bold text-white"
                      >
                        Add friend
                      </button>
                    )
                  }
                />
              );
            })
          )}
          <p className="mt-6 text-center text-xs text-ink-faint">
            Signed in as {me.name}. Keep your profile public so others can discover you.
          </p>
        </section>
      )}
    </div>
  );
}

function PersonRow({
  name,
  handle,
  bio,
  interests,
  grad,
  href,
  actions,
}: {
  name: string;
  handle?: string | null;
  bio?: string | null;
  interests?: string[];
  grad: "coral" | "rose" | "lilac" | "sky" | "butter" | "sage" | "peach";
  href?: string;
  actions?: ReactNode;
}) {
  const body = (
    <>
      <Avatar grad={grad} label={name} size={44} />
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-bold text-ink">{name}</p>
        {handle && <p className="truncate text-xs text-ink-faint">@{handle}</p>}
        {bio && !interests?.length && (
          <p className="mt-0.5 truncate text-xs text-ink-soft">{bio}</p>
        )}
        {interests && interests.length > 0 && (
          <p className="mt-0.5 truncate text-xs text-ink-soft">
            {interests
              .slice(0, 3)
              .map((t) => `${interestEmoji(t)} ${interestLabel(t)}`)
              .join(" · ")}
          </p>
        )}
      </div>
    </>
  );
  return (
    <div className="flex items-center gap-3 rounded-xl px-2 py-2.5 hover:bg-ink/5">
      {href ? (
        <Link href={href} className="flex min-w-0 flex-1 items-center gap-3">
          {body}
        </Link>
      ) : (
        <div className="flex min-w-0 flex-1 items-center gap-3">{body}</div>
      )}
      <div className="flex shrink-0 items-center gap-1.5">{actions}</div>
    </div>
  );
}

function Empty({
  title,
  body,
  cta,
}: {
  title: string;
  body: string;
  cta?: { label: string; onClick?: () => void; href?: string };
}) {
  return (
    <div className="rounded-3xl border border-dashed border-line bg-surface/60 px-6 py-10 text-center">
      <p className="font-display text-lg font-bold text-ink">{title}</p>
      <p className="mt-1 text-sm text-ink-soft">{body}</p>
      {cta?.href ? (
        <Link
          href={cta.href}
          className="mt-4 inline-flex rounded-full bg-coral px-5 py-2.5 text-sm font-bold text-white"
        >
          {cta.label}
        </Link>
      ) : cta?.onClick ? (
        <button
          onClick={cta.onClick}
          className="mt-4 inline-flex rounded-full bg-coral px-5 py-2.5 text-sm font-bold text-white"
        >
          {cta.label}
        </button>
      ) : null}
    </div>
  );
}
