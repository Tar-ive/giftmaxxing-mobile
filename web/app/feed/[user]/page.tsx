"use client";

import { useEffect, useState } from "react";
import { useParams, useRouter, notFound } from "next/navigation";
import { GRADIENTS } from "@/lib/data";
import { USERS, profilePosts } from "@/lib/social";
import { useCurrentUser, getClerkImageUrl } from "@/lib/identity";
import {
  loadProfile,
  setProfileVisibility,
  INTEREST_META,
  MATERIALISTIC_META,
  BUDGET_RANGE_META,
  type UserProfile,
  type GiftRole,
  type GiftStyle,
  type ProfileVisibility,
} from "@/lib/onboarding";
import { Icons } from "@/components/ui";
import { useStore } from "@/components/app/store";
import {
  getMyUserId,
  fetchConnections,
  fetchSavedIds,
  relativeTime,
  isApiConfigured,
  type SoftConnection,
} from "@/lib/api";
import {
  acceptFriend,
  getFriendshipStatus,
  listFriends,
  openDm,
  requestFriend,
  type Friendship,
} from "@/lib/friends";
import Link from "next/link";

const ROLE_META: Record<GiftRole, { label: string; emoji: string }> = {
  giver: { label: "Gift giver", emoji: "🎁" },
  taker: { label: "Gift receiver", emoji: "🎀" },
  both: { label: "Gives & receives", emoji: "🤝" },
};

const STYLE_META: Record<GiftStyle, { label: string; emoji: string }> = {
  thoughtful: { label: "Thoughtful gifter", emoji: "💌" },
  materialistic: { label: "Loves nice things", emoji: "🛍️" },
  mix: { label: "Thoughtful + a treat", emoji: "🎨" },
};

export default function ProfilePage() {
  const params = useParams<{ user: string }>();
  const router = useRouter();
  const userId = params.user;
  const { toggleFollow, isFollowing, openPost, posts: storePosts, claimItem, unclaimItem, claims } = useStore();
  const me = useCurrentUser();
  const [tab, setTab] = useState<"posts" | "saved" | "friends">("posts");

  const isMe = userId === "you";
  const baseU = USERS[userId];

  // The signed-in user's onboarding profile (taste) + their soft-profile
  // "friends". Only meaningful for "you"; other profiles render from the demo
  // social graph and never expose the current user's connections.
  const [profile, setProfile] = useState<UserProfile | null>(null);
  const [friends, setFriends] = useState<SoftConnection[]>([]);
  const [hardFriends, setHardFriends] = useState<Friendship[]>([]);
  const [friendStatus, setFriendStatus] = useState<"none" | "pending" | "accepted" | "incoming">("none");
  const [friendBusy, setFriendBusy] = useState(false);
  const [ownerSavedIds, setOwnerSavedIds] = useState<Set<string> | null>(null);

  useEffect(() => {
    if (!isMe) return;
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setProfile(loadProfile());
  }, [isMe]);

  useEffect(() => {
    if (!isMe) return;
    const uid = getMyUserId();
    if (!uid) return;
    let cancelled = false;
    (async () => {
      const [{ items }, hard] = await Promise.all([
        fetchConnections(uid),
        listFriends(uid, "accepted"),
      ]);
      if (!cancelled) {
        setFriends(items);
        setHardFriends(hard);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [isMe]);

  useEffect(() => {
    if (isMe) return;
    const uid = getMyUserId() ?? "you";
    let cancelled = false;
    (async () => {
      const s = await getFriendshipStatus(uid, userId);
      if (cancelled) return;
      if (s.status === "pending" && s.incoming) setFriendStatus("incoming");
      else setFriendStatus(s.status);
    })();
    return () => {
      cancelled = true;
    };
  }, [isMe, userId]);

  // For non-self profiles: fetch the profile owner's saved item IDs from the API
  // so the Wishlist tab shows their saves (not the viewer's).
  useEffect(() => {
    if (isMe || !isApiConfigured()) return;
    let cancelled = false;
    (async () => {
      const ids = await fetchSavedIds(userId);
      if (!cancelled) setOwnerSavedIds(ids);
    })();
    return () => { cancelled = true; };
  }, [isMe, userId]);

  if (!baseU && !isMe) return notFound();
  const u = isMe ? me : baseU;
  // For the current user, merge user-created posts (from store) with the static
  // profile grid so posted finds persist and show on the profile.
  const grid = isMe
    ? [...storePosts.filter((p) => p.user === "you"), ...profilePosts(userId).filter((p) => !storePosts.some((sp) => sp.id === p.id))].slice(0, 12)
    : profilePosts(userId);
  const visibility: ProfileVisibility = profile?.visibility ?? "public";

  // Combined taste chips (interests + materialistic categories) for the summary.
  const tasteChips =
    isMe && profile
      ? [
          ...profile.interests.map((t) => INTEREST_META[t]),
          ...profile.materialisticCategories.map((c) => MATERIALISTIC_META[c]),
        ].filter(Boolean)
      : [];

  // For self: saved posts from the store. For others: posts matching IDs fetched
  // from the API (the owner's saves). Falls back to empty until the API responds.
  const savedPosts = isMe
    ? storePosts.filter((p) => p.saved)
    : ownerSavedIds
      ? storePosts.filter((p) => ownerSavedIds.has(p.id))
      : [];

  const tabs = isMe
    ? ([
        { id: "posts", label: "Finds", icon: "menu" },
        { id: "saved", label: "Wishlist", icon: "bookmark" },
        { id: "friends", label: "Tagged", icon: "users" },
      ] as const)
    : ([
        { id: "posts", label: "Finds", icon: "menu" },
        { id: "saved", label: "Wishlist", icon: "bookmark" },
      ] as const);

  const toggleVisibility = () => {
    const next: ProfileVisibility = visibility === "public" ? "private" : "public";
    setProfileVisibility(next);
    setProfile((prev) => (prev ? { ...prev, visibility: next } : prev));
  };

  const clerkImageUrl = isMe ? getClerkImageUrl() : null;

  return (
    <div className="mx-auto max-w-4xl px-4 py-8 sm:py-10">
      {/* header */}
      <header className="flex flex-col items-center gap-6 sm:flex-row sm:items-start sm:gap-12">
        {isMe && clerkImageUrl ? (
          <img
            src={clerkImageUrl}
            alt={u.name}
            className="h-24 w-24 shrink-0 rounded-full object-cover shadow-md sm:h-36 sm:w-36"
          />
        ) : (
          <div
            className="grid h-24 w-24 shrink-0 place-items-center rounded-full text-4xl font-bold text-white shadow-md sm:h-36 sm:w-36"
            style={{ background: GRADIENTS[u.grad] }}
          >
            {u.name.charAt(0)}
          </div>
        )}

        <div className="flex-1 text-center sm:text-left">
          <div className="flex flex-col items-center gap-4 sm:flex-row sm:items-center">
            <h1 className="text-xl font-semibold text-ink">{u.handle}</h1>
            <div className="flex gap-2">
              {isMe ? (
                <>
                  <button
                    onClick={() => router.push("/onboarding")}
                    className="rounded-lg bg-coral px-4 py-1.5 text-sm font-bold text-white"
                  >
                    Edit taste
                  </button>
                  <button
                    onClick={() => router.push("/feed/settings")}
                    className="rounded-lg bg-ink/5 px-4 py-1.5 text-sm font-bold text-ink"
                  >
                    Settings
                  </button>
                  <Link
                    href="/feed/friends"
                    className="rounded-lg bg-ink/5 px-4 py-1.5 text-sm font-bold text-ink"
                  >
                    Friends
                  </Link>
                </>
              ) : (
                <>
                  <button
                    onClick={() => toggleFollow(u.id)}
                    className={`rounded-lg px-6 py-1.5 text-sm font-bold ${
                      isFollowing(u.id)
                        ? "bg-ink/5 text-ink"
                        : "bg-coral text-white"
                    }`}
                  >
                    {isFollowing(u.id) ? "Following" : "Follow"}
                  </button>
                  {friendStatus === "accepted" ? (
                    <button
                      disabled={friendBusy}
                      onClick={() => {
                        void (async () => {
                          setFriendBusy(true);
                          const tid = await openDm({
                            userId: getMyUserId() ?? "you",
                            otherUserId: u.id,
                          });
                          setFriendBusy(false);
                          if (tid) router.push(`/feed/messages?dm=${encodeURIComponent(tid)}`);
                        })();
                      }}
                      className="rounded-lg bg-ink px-4 py-1.5 text-sm font-bold text-cream"
                    >
                      Message
                    </button>
                  ) : friendStatus === "incoming" ? (
                    <button
                      disabled={friendBusy}
                      onClick={() => {
                        void (async () => {
                          setFriendBusy(true);
                          await acceptFriend({
                            userId: getMyUserId() ?? "you",
                            fromUserId: u.id,
                          });
                          setFriendStatus("accepted");
                          setFriendBusy(false);
                        })();
                      }}
                      className="rounded-lg bg-coral px-4 py-1.5 text-sm font-bold text-white"
                    >
                      Accept
                    </button>
                  ) : friendStatus === "pending" ? (
                    <span className="rounded-lg bg-ink/5 px-4 py-1.5 text-sm font-bold text-ink-faint">
                      Requested
                    </span>
                  ) : (
                    <button
                      disabled={friendBusy}
                      onClick={() => {
                        void (async () => {
                          setFriendBusy(true);
                          await requestFriend({
                            fromUserId: getMyUserId() ?? "you",
                            toUserId: u.id,
                            toName: u.name,
                            toHandle: u.handle,
                          });
                          setFriendStatus("pending");
                          setFriendBusy(false);
                        })();
                      }}
                      className="rounded-lg bg-coral px-4 py-1.5 text-sm font-bold text-white"
                    >
                      Add friend
                    </button>
                  )}
                  <Link
                    href={`/feed?giftFor=${encodeURIComponent(u.id)}`}
                    className="rounded-lg bg-ink/5 px-4 py-1.5 text-sm font-bold text-ink"
                  >
                    Gift
                  </Link>
                </>
              )}
            </div>
          </div>

          {/* stats — real posts + friends counts (no fake follower numbers) */}
          <div className="mt-5 flex justify-center gap-8 sm:justify-start">
            <Stat n={grid.length} label="posts" />
            {isMe && (
              <Stat n={hardFriends.length + friends.length} label="friends" />
            )}
          </div>

          {/* name + taste summary */}
          <div className="mt-4">
            <p className="font-bold text-ink">{u.name}</p>
            {!isMe && u.bio && <p className="text-sm text-ink-soft">{u.bio}</p>}
          </div>

          {isMe && (
            <div className="mt-3">
              {profile ? (
                <>
                  <div className="flex flex-wrap justify-center gap-2 sm:justify-start">
                    <Tag
                      emoji={ROLE_META[profile.role].emoji}
                      text={ROLE_META[profile.role].label}
                      highlight
                    />
                    <Tag
                      emoji={STYLE_META[profile.style].emoji}
                      text={STYLE_META[profile.style].label}
                    />
                    <Tag
                      emoji={BUDGET_RANGE_META[profile.dealPreferences.budgetRange].emoji}
                      text={BUDGET_RANGE_META[profile.dealPreferences.budgetRange].label}
                    />
                  </div>

                  {tasteChips.length > 0 && (
                    <div className="mt-3">
                      <p className="mb-1.5 text-xs font-bold uppercase tracking-wider text-ink-faint">
                        Into
                      </p>
                      <div className="flex flex-wrap justify-center gap-1.5 sm:justify-start">
                        {tasteChips.map((c, i) => (
                          <span
                            key={i}
                            className="inline-flex items-center gap-1 rounded-full bg-ink/5 px-2.5 py-1 text-xs font-semibold text-ink-soft"
                          >
                            <span>{c.emoji}</span> {c.label}
                          </span>
                        ))}
                      </div>
                    </div>
                  )}
                </>
              ) : (
                <p className="text-sm text-ink-soft">
                  Finish onboarding to build your taste profile.
                </p>
              )}

              <VisibilityToggle
                visibility={visibility}
                onToggle={toggleVisibility}
                disabled={!profile}
              />
            </div>
          )}
        </div>
      </header>

      {/* tabs */}
      <div className="mt-10 flex justify-center gap-12 border-t border-line">
        {tabs.map((t) => {
          const Ico = Icons[t.icon];
          const active = tab === t.id;
          return (
            <button
              key={t.id}
              onClick={() => setTab(t.id)}
              className={`-mt-px flex items-center gap-2 border-t-2 py-3 text-xs font-bold uppercase tracking-wider ${
                active
                  ? "border-ink text-ink"
                  : "border-transparent text-ink-faint"
              }`}
            >
              <Ico size={16} /> <span>{t.label}</span>
            </button>
          );
        })}
      </div>

      {/* content */}
      {tab === "friends" ? (
        <FriendsList soft={friends} hard={hardFriends} />
      ) : tab === "saved" ? (
        savedPosts.length === 0 ? (
          <p className="py-20 text-center text-sm text-ink-faint">
            {isMe ? "No saved posts yet. Bookmark finds from your feed." : "No wishlist items yet."}
          </p>
        ) : (
          <div className="mt-2 space-y-2">
            {savedPosts.map((p) => {
              const claim = claims[p.id];
              return (
                <div key={p.id} className={`flex items-center gap-3 rounded-xl border border-line bg-surface p-3 transition-opacity ${claim ? "opacity-60" : ""}`}>
                  <button
                    onClick={() => openPost(p.id)}
                    className="relative grid h-16 w-16 shrink-0 place-items-center overflow-hidden rounded-lg"
                    style={{ background: GRADIENTS[p.product.grad] }}
                  >
                    <span className="text-2xl">{p.product.emoji}</span>
                    {p.product.image && (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img src={p.product.image} alt={p.product.name} className="absolute inset-0 h-full w-full object-cover" onError={(e) => { e.currentTarget.style.display = "none"; }} />
                    )}
                  </button>
                  <div className="min-w-0 flex-1">
                    <p className={`text-sm font-bold text-ink ${claim ? "line-through" : ""}`}>
                      {p.product.name}
                    </p>
                    <p className="text-xs text-ink-faint">
                      {p.product.brand} · ${p.product.price}
                    </p>
                    {claim && (
                      <span className="mt-1 inline-flex items-center gap-1 rounded-full bg-emerald-50 px-2 py-0.5 text-[11px] font-semibold text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400">
                        <Icons.check size={12} /> Claimed by {claim.claimedBy}
                      </span>
                    )}
                  </div>
                  {claim ? (
                    <button
                      onClick={() => unclaimItem(p.id)}
                      className="shrink-0 rounded-lg bg-ink/5 px-3 py-1.5 text-xs font-bold text-ink-soft hover:bg-ink/10"
                    >
                      Unclaim
                    </button>
                  ) : (
                    <button
                      onClick={() => claimItem(p.id)}
                      className="shrink-0 rounded-lg bg-coral px-3 py-1.5 text-xs font-bold text-white hover:opacity-90"
                    >
                      Claim
                    </button>
                  )}
                </div>
              );
            })}
          </div>
        )
      ) : grid.length === 0 ? (
        <p className="py-20 text-center text-sm text-ink-faint">No posts yet.</p>
      ) : (
        <div className="mt-1 grid grid-cols-3 gap-1 sm:gap-2">
          {grid.map((p) => (
            <button
              key={p.id}
              onClick={() => openPost(p.id)}
              className="group relative grid aspect-square place-items-center overflow-hidden"
              style={{ background: GRADIENTS[p.product.grad] }}
            >
              <span className="text-5xl sm:text-6xl">{p.product.emoji}</span>
              {p.product.image && (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={p.product.image} alt={p.product.name} className="absolute inset-0 h-full w-full object-cover" onError={(e) => { e.currentTarget.style.display = "none"; }} />
              )}
              <div className="absolute inset-0 flex items-center justify-center gap-5 bg-black/40 text-white opacity-0 transition-opacity group-hover:opacity-100">
                <span className="flex items-center gap-1.5 font-bold">
                  <Icons.heartFill size={20} /> {p.likes}
                </span>
                <span className="flex items-center gap-1.5 font-bold">
                  <Icons.comment size={20} /> {p.comments.length}
                </span>
              </div>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

function Tag({
  emoji,
  text,
  highlight,
}: {
  emoji: string;
  text: string;
  highlight?: boolean;
}) {
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-sm font-semibold ${
        highlight ? "bg-coral-soft text-coral" : "bg-ink/5 text-ink-soft"
      }`}
    >
      <span>{emoji}</span> {text}
    </span>
  );
}

function VisibilityToggle({
  visibility,
  onToggle,
  disabled,
}: {
  visibility: ProfileVisibility;
  onToggle: () => void;
  disabled?: boolean;
}) {
  const isPublic = visibility === "public";
  return (
    <div className="mt-4 flex items-center justify-between gap-4 rounded-2xl border border-line bg-surface px-4 py-3">
      <div className="flex items-center gap-3 text-left">
        <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-ink/5 text-lg">
          {isPublic ? "🌍" : "🔒"}
        </span>
        <div>
          <p className="text-sm font-bold text-ink">
            {isPublic ? "Public profile" : "Private profile"}
          </p>
          <p className="text-xs text-ink-soft">
            {isPublic
              ? "Anyone can see your posts and friends."
              : "Only you can see your profile."}
          </p>
        </div>
      </div>
      <button
        type="button"
        role="switch"
        aria-checked={isPublic}
        aria-label="Toggle profile visibility"
        disabled={disabled}
        onClick={onToggle}
        className={`relative inline-flex h-6 w-11 shrink-0 items-center rounded-full transition-colors disabled:cursor-not-allowed disabled:opacity-40 ${
          isPublic ? "bg-coral" : "bg-ink/20"
        }`}
      >
        <span
          className={`inline-block h-5 w-5 transform rounded-full bg-white shadow transition-transform ${
            isPublic ? "translate-x-[22px]" : "translate-x-0.5"
          }`}
        />
      </button>
    </div>
  );
}

function FriendsList({
  soft,
  hard,
}: {
  soft: SoftConnection[];
  hard: Friendship[];
}) {
  if (soft.length === 0 && hard.length === 0) {
    return (
      <div className="py-16 text-center">
        <p className="text-sm text-ink-faint">
          No friends yet. Discover people on Giftmaxxing, connect inside a circle,
          or share a swipe challenge.
        </p>
        <Link
          href="/feed/friends"
          className="mt-4 inline-flex rounded-full bg-coral px-5 py-2.5 text-sm font-bold text-white"
        >
          Find friends
        </Link>
      </div>
    );
  }
  return (
    <div className="mt-2">
      {hard.length > 0 && (
        <div className="mb-4">
          <p className="mb-2 text-xs font-bold uppercase tracking-wide text-ink-faint">
            On Giftmaxxing
          </p>
          <div className="divide-y divide-line">
            {hard.map((f) => (
              <div key={f.friendId} className="flex items-center gap-3 py-3">
                <span className="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-coral-soft text-sm font-extrabold text-ink">
                  {(f.name ?? f.friendId).charAt(0).toUpperCase()}
                </span>
                <div className="min-w-0 flex-1">
                  <p className="text-sm font-bold text-ink">
                    {f.name ?? f.friendId}
                    {f.handle && (
                      <span className="ml-1 font-normal text-ink-faint">@{f.handle}</span>
                    )}
                  </p>
                  <p className="text-xs text-ink-faint">Friends · message & gift</p>
                </div>
                <Link
                  href="/feed/messages"
                  className="rounded-full bg-ink px-3 py-1.5 text-xs font-bold text-cream"
                >
                  Message
                </Link>
              </div>
            ))}
          </div>
        </div>
      )}
      {soft.length > 0 && (
        <div>
          <p className="mb-2 text-xs font-bold uppercase tracking-wide text-ink-faint">
            Soft profiles (from challenges)
          </p>
          <div className="divide-y divide-line">
            {soft.map((f) => {
              const tags = [...(f.vibes ?? []), ...(f.interests ?? [])].slice(0, 6);
              return (
                <div key={f.connectionId} className="flex items-start gap-3 py-4">
                  <span className="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-coral-soft text-xl">
                    🎁
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="text-sm font-bold text-ink">
                      {f.guestName}
                      {f.guestHandle && (
                        <span className="ml-1 font-normal text-ink-faint">
                          @{f.guestHandle}
                        </span>
                      )}
                    </p>
                    <p className="text-xs text-ink-faint">
                      Taste saved {relativeTime(f.createdAt) || "recently"}
                      {f.birthday ? ` · 🎂 ${f.birthday}` : ""}
                      {typeof f.yesCount === "number" && typeof f.totalSwipes === "number"
                        ? ` · liked ${f.yesCount}/${f.totalSwipes}`
                        : ""}
                    </p>
                    {tags.length > 0 && (
                      <div className="mt-2 flex flex-wrap gap-1">
                        {tags.map((t, i) => (
                          <span
                            key={i}
                            className="rounded-full bg-ink/5 px-2 py-0.5 text-[11px] font-medium text-ink-soft"
                          >
                            {t}
                          </span>
                        ))}
                      </div>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}

function Stat({ n, label }: { n: number; label: string }) {
  return (
    <p className="text-sm text-ink">
      <span className="font-bold">{n.toLocaleString()}</span>{" "}
      <span className="text-ink-soft">{label}</span>
    </p>
  );
}
