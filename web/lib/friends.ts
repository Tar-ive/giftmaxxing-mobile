"use client";

// Friends, public people discovery, and 1:1 DMs.
// Talks to the AWS friends APIs (infra/src/friends-routes.mjs). When the API
// isn't configured / unreachable, falls back to localStorage so the UI still
// works in demo mode — same pattern as pools + soft connections.

import { apiFetch, isApiConfigured, getMyUserId } from "@/lib/api";
import { USERS } from "@/lib/social";
import { loadProfile } from "@/lib/onboarding";
import { getCurrentUser } from "@/lib/identity";

export type PublicPerson = {
  userId: string;
  name: string;
  handle: string;
  bio?: string | null;
  imageUrl?: string | null;
  interests?: string[];
  materialisticCategories?: string[];
  style?: string | null;
  role?: string | null;
  visibility?: "public" | "private";
};

export type Friendship = {
  friendId: string;
  status: "pending" | "accepted" | "none";
  requestedBy?: string | null;
  incoming?: boolean;
  circleId?: string | null;
  createdAt?: number;
  updatedAt?: number;
  name?: string | null;
  handle?: string | null;
  bio?: string | null;
  interests?: string[];
};

export type DmThread = {
  threadId: string;
  otherUserId: string;
  otherName?: string | null;
  otherHandle?: string | null;
  lastText?: string | null;
  lastAt?: number;
};

export type DmMessage = {
  id: string;
  userId: string;
  name: string;
  text: string;
  at: number;
};

const LOCAL_FRIENDS_KEY = "giftmaxxing_friends";
const LOCAL_DMS_KEY = "giftmaxxing_friend_dms";
export const FRIENDS_EVENT = "giftmaxxing:friends";

type LocalStore = {
  // userId → friendId → edge
  edges: Record<string, Record<string, Friendship>>;
};

type LocalDmStore = {
  threads: Record<
    string,
    {
      threadId: string;
      userA: string;
      userB: string;
      messages: DmMessage[];
      lastText: string | null;
      lastAt: number;
    }
  >;
};

function notify() {
  if (typeof window !== "undefined") {
    window.dispatchEvent(new Event(FRIENDS_EVENT));
  }
}

function loadLocalFriends(): LocalStore {
  if (typeof window === "undefined") return { edges: {} };
  try {
    const raw = localStorage.getItem(LOCAL_FRIENDS_KEY);
    if (raw) return JSON.parse(raw) as LocalStore;
  } catch {
    /* ignore */
  }
  return { edges: {} };
}

function saveLocalFriends(store: LocalStore) {
  try {
    localStorage.setItem(LOCAL_FRIENDS_KEY, JSON.stringify(store));
    notify();
  } catch {
    /* quota */
  }
}

function loadLocalDms(): LocalDmStore {
  if (typeof window === "undefined") return { threads: {} };
  try {
    const raw = localStorage.getItem(LOCAL_DMS_KEY);
    if (raw) return JSON.parse(raw) as LocalDmStore;
  } catch {
    /* ignore */
  }
  return { threads: {} };
}

function saveLocalDms(store: LocalDmStore) {
  try {
    localStorage.setItem(LOCAL_DMS_KEY, JSON.stringify(store));
    notify();
  } catch {
    /* quota */
  }
}

function localThreadId(a: string, b: string): string {
  const [x, y] = [a, b].sort();
  return `DM#${x}__${y}`;
}

/** Demo directory: static USERS + the current user's public profile. */
function demoPeople(q = ""): PublicPerson[] {
  const t = q.trim().toLowerCase();
  const me = getCurrentUser();
  const profile = loadProfile();
  const self: PublicPerson = {
    userId: getMyUserId() ?? "you",
    name: me.name,
    handle: me.handle,
    bio: profile ? `Into ${profile.interests.slice(0, 3).join(", ")}` : me.bio ?? null,
    interests: profile?.interests ?? [],
    materialisticCategories: profile?.materialisticCategories ?? [],
    style: profile?.style ?? null,
    role: profile?.role ?? null,
    visibility: profile?.visibility ?? "public",
  };
  const others = Object.values(USERS)
    .filter((u) => u.id !== "you" && u.id !== "maxi")
    .map(
      (u): PublicPerson => ({
        userId: u.id,
        name: u.name,
        handle: u.handle,
        bio: u.bio ?? null,
        interests: [],
      })
    );
  return [self, ...others].filter((p) => {
    if (p.visibility === "private") return false;
    if (!t) return p.userId !== (getMyUserId() ?? "you");
    const hay = `${p.name} ${p.handle} ${(p.interests ?? []).join(" ")}`.toLowerCase();
    return hay.includes(t) && p.userId !== (getMyUserId() ?? "you");
  });
}

// ── People discovery ─────────────────────────────────────────────────────────

export async function searchPeople(q = "", limit = 24): Promise<PublicPerson[]> {
  if (isApiConfigured()) {
    try {
      const params = new URLSearchParams();
      if (q.trim()) params.set("q", q.trim());
      params.set("limit", String(limit));
      const res = await apiFetch(`/people?${params}`, {
        headers: { accept: "application/json" },
      });
      if (res.ok) {
        const data = (await res.json()) as { items?: PublicPerson[] };
        const items = data.items ?? [];
        // Fall back to demo directory if the live directory is empty (fresh env).
        if (items.length > 0) return items;
      }
    } catch {
      /* fall through */
    }
  }
  return demoPeople(q).slice(0, limit);
}

export async function fetchPerson(userId: string): Promise<PublicPerson | null> {
  if (!userId) return null;
  if (isApiConfigured()) {
    try {
      const res = await apiFetch(`/people/${encodeURIComponent(userId)}`, {
        headers: { accept: "application/json" },
      });
      if (res.ok) {
        const data = (await res.json()) as { item?: PublicPerson };
        return data.item ?? null;
      }
    } catch {
      /* fall through */
    }
  }
  return demoPeople("").find((p) => p.userId === userId) ?? demoPeople(userId)[0] ?? null;
}

// ── Friendships ──────────────────────────────────────────────────────────────

export async function listFriends(
  userId: string,
  status?: "pending" | "accepted"
): Promise<Friendship[]> {
  if (!userId) return [];
  if (isApiConfigured()) {
    try {
      const params = new URLSearchParams({ userId });
      if (status) params.set("status", status);
      const res = await apiFetch(`/friends?${params}`, {
        headers: { accept: "application/json" },
      });
      if (res.ok) {
        const data = (await res.json()) as { items?: Friendship[] };
        return data.items ?? [];
      }
    } catch {
      /* fall through */
    }
  }
  const store = loadLocalFriends();
  let items = Object.values(store.edges[userId] ?? {});
  if (status) items = items.filter((f) => f.status === status);
  return items;
}

export async function getFriendshipStatus(
  userId: string,
  otherId: string
): Promise<{ status: "none" | "pending" | "accepted"; incoming?: boolean; requestedBy?: string | null }> {
  if (!userId || !otherId) return { status: "none" };
  if (isApiConfigured()) {
    try {
      const params = new URLSearchParams({ userId, otherId });
      const res = await apiFetch(`/friends/status?${params}`, {
        headers: { accept: "application/json" },
      });
      if (res.ok) {
        return (await res.json()) as {
          status: "none" | "pending" | "accepted";
          incoming?: boolean;
          requestedBy?: string | null;
        };
      }
    } catch {
      /* fall through */
    }
  }
  const edge = loadLocalFriends().edges[userId]?.[otherId];
  if (!edge) return { status: "none" };
  return {
    status: edge.status === "accepted" ? "accepted" : "pending",
    incoming: !!edge.incoming,
    requestedBy: edge.requestedBy ?? null,
  };
}

export async function requestFriend(opts: {
  fromUserId: string;
  toUserId: string;
  circleId?: string;
  toName?: string;
  toHandle?: string;
}): Promise<{ ok: boolean; status?: string }> {
  const { fromUserId, toUserId, circleId, toName, toHandle } = opts;
  if (!fromUserId || !toUserId || fromUserId === toUserId) return { ok: false };

  if (isApiConfigured()) {
    try {
      const res = await apiFetch(`/friends/request`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ fromUserId, toUserId, circleId }),
      });
      if (res.ok) return (await res.json()) as { ok: boolean; status?: string };
    } catch {
      /* fall through */
    }
  }

  const store = loadLocalFriends();
  store.edges[fromUserId] ??= {};
  store.edges[toUserId] ??= {};
  const existing = store.edges[fromUserId][toUserId];
  if (existing?.status === "accepted") return { ok: true, status: "accepted" };
  if (existing?.status === "pending" && existing.requestedBy === toUserId) {
    return acceptFriend({ userId: fromUserId, fromUserId: toUserId });
  }
  const now = Date.now();
  const me = getCurrentUser();
  store.edges[fromUserId][toUserId] = {
    friendId: toUserId,
    status: "pending",
    requestedBy: fromUserId,
    circleId: circleId ?? null,
    createdAt: now,
    incoming: false,
    name: toName ?? USERS[toUserId]?.name ?? toUserId,
    handle: toHandle ?? USERS[toUserId]?.handle ?? null,
  };
  store.edges[toUserId][fromUserId] = {
    friendId: fromUserId,
    status: "pending",
    requestedBy: fromUserId,
    circleId: circleId ?? null,
    createdAt: now,
    incoming: true,
    name: me.name,
    handle: me.handle,
  };
  saveLocalFriends(store);
  return { ok: true, status: "pending" };
}

export async function acceptFriend(opts: {
  userId: string;
  fromUserId: string;
}): Promise<{ ok: boolean; status?: string }> {
  const { userId, fromUserId } = opts;
  if (!userId || !fromUserId) return { ok: false };

  if (isApiConfigured()) {
    try {
      const res = await apiFetch(`/friends/accept`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ userId, fromUserId }),
      });
      if (res.ok) return (await res.json()) as { ok: boolean; status?: string };
    } catch {
      /* fall through */
    }
  }

  const store = loadLocalFriends();
  const now = Date.now();
  for (const [a, b] of [
    [userId, fromUserId],
    [fromUserId, userId],
  ] as const) {
    store.edges[a] ??= {};
    store.edges[a][b] = {
      ...(store.edges[a][b] ?? { friendId: b, requestedBy: fromUserId }),
      friendId: b,
      status: "accepted",
      updatedAt: now,
      incoming: false,
    };
  }
  saveLocalFriends(store);
  await openDm({ userId, otherUserId: fromUserId });
  return { ok: true, status: "accepted" };
}

export async function removeFriend(opts: {
  userId: string;
  friendId: string;
}): Promise<boolean> {
  const { userId, friendId } = opts;
  if (!userId || !friendId) return false;

  if (isApiConfigured()) {
    try {
      const res = await apiFetch(`/friends/remove`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ userId, fromUserId: friendId, friendId }),
      });
      if (res.ok) return true;
    } catch {
      /* fall through */
    }
  }

  const store = loadLocalFriends();
  if (store.edges[userId]) delete store.edges[userId][friendId];
  if (store.edges[friendId]) delete store.edges[friendId][userId];
  saveLocalFriends(store);
  return true;
}

// ── Direct messages ──────────────────────────────────────────────────────────

export async function openDm(opts: {
  userId: string;
  otherUserId: string;
}): Promise<string | null> {
  const { userId, otherUserId } = opts;
  if (!userId || !otherUserId) return null;

  if (isApiConfigured()) {
    try {
      const res = await apiFetch(`/dms/open`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ userId, otherUserId }),
      });
      if (res.ok) {
        const data = (await res.json()) as { threadId?: string };
        return data.threadId ?? null;
      }
    } catch {
      /* fall through */
    }
  }

  const tid = localThreadId(userId, otherUserId);
  const store = loadLocalDms();
  if (!store.threads[tid]) {
    const other = USERS[otherUserId];
    store.threads[tid] = {
      threadId: tid,
      userA: userId,
      userB: otherUserId,
      messages: [],
      lastText: null,
      lastAt: Date.now(),
    };
    void other;
    saveLocalDms(store);
  }
  return tid;
}

export async function listDms(userId: string): Promise<DmThread[]> {
  if (!userId) return [];
  if (isApiConfigured()) {
    try {
      const res = await apiFetch(`/dms?userId=${encodeURIComponent(userId)}`, {
        headers: { accept: "application/json" },
      });
      if (res.ok) {
        const data = (await res.json()) as { items?: DmThread[] };
        return data.items ?? [];
      }
    } catch {
      /* fall through */
    }
  }
  const store = loadLocalDms();
  return Object.values(store.threads)
    .filter((t) => t.userA === userId || t.userB === userId)
    .map((t) => {
      const otherUserId = t.userA === userId ? t.userB : t.userA;
      const other = USERS[otherUserId];
      return {
        threadId: t.threadId,
        otherUserId,
        otherName: other?.name ?? otherUserId,
        otherHandle: other?.handle ?? null,
        lastText: t.lastText,
        lastAt: t.lastAt,
      };
    })
    .sort((a, b) => (b.lastAt ?? 0) - (a.lastAt ?? 0));
}

export async function fetchDmMessages(threadId: string): Promise<DmMessage[]> {
  if (!threadId) return [];
  if (isApiConfigured()) {
    try {
      const res = await apiFetch(`/dms/${encodeURIComponent(threadId)}/messages`, {
        headers: { accept: "application/json" },
      });
      if (res.ok) {
        const data = (await res.json()) as { items?: DmMessage[] };
        return data.items ?? [];
      }
    } catch {
      /* fall through */
    }
  }
  return loadLocalDms().threads[threadId]?.messages ?? [];
}

export async function sendDmMessage(opts: {
  threadId: string;
  userId: string;
  name: string;
  text: string;
}): Promise<DmMessage | null> {
  const { threadId, userId, name, text } = opts;
  const trimmed = text.trim();
  if (!threadId || !userId || !trimmed) return null;

  if (isApiConfigured()) {
    try {
      const res = await apiFetch(`/dms/${encodeURIComponent(threadId)}/messages`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ userId, name, text: trimmed }),
      });
      if (res.ok) {
        const data = (await res.json()) as { message?: DmMessage };
        notify();
        return data.message ?? null;
      }
    } catch {
      /* fall through */
    }
  }

  const store = loadLocalDms();
  const thread = store.threads[threadId];
  if (!thread) return null;
  const msg: DmMessage = {
    id: `MSG#${Date.now()}`,
    userId,
    name,
    text: trimmed.slice(0, 1000),
    at: Date.now(),
  };
  thread.messages.push(msg);
  thread.lastText = msg.text.slice(0, 140);
  thread.lastAt = msg.at;
  saveLocalDms(store);
  return msg;
}

// ── Circle account claim ─────────────────────────────────────────────────────

export async function claimCircleSeat(opts: {
  circleId: string;
  userId: string;
  memberName: string;
}): Promise<boolean> {
  const { circleId, userId, memberName } = opts;
  if (!circleId || !userId || !memberName) return false;
  if (!isApiConfigured()) {
    // Demo: remember the claim locally so the circle UI can show Connect.
    try {
      const key = `giftmaxxing_circle_claims`;
      const raw = localStorage.getItem(key);
      const map = raw ? (JSON.parse(raw) as Record<string, Record<string, string>>) : {};
      map[circleId] ??= {};
      map[circleId][memberName.toLowerCase()] = userId;
      localStorage.setItem(key, JSON.stringify(map));
      notify();
    } catch {
      /* ignore */
    }
    return true;
  }
  try {
    const res = await apiFetch(`/circles/${encodeURIComponent(circleId)}/claim`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ userId, memberName }),
    });
    return res.ok;
  } catch {
    return false;
  }
}

export function loadLocalCircleClaims(circleId: string): Record<string, string> {
  if (typeof window === "undefined") return {};
  try {
    const raw = localStorage.getItem("giftmaxxing_circle_claims");
    const map = raw ? (JSON.parse(raw) as Record<string, Record<string, string>>) : {};
    return map[circleId] ?? {};
  } catch {
    return {};
  }
}
