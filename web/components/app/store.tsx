"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { type Post, type GroupChat, GROUP_CHATS } from "@/lib/social";
import { buildPinFeed } from "@/lib/feed-builder";
import { loadProfile } from "@/lib/onboarding";
import { tasteFromProfile, feedPersonalization } from "@/lib/taste";
import { fetchFeed, isApiConfigured, getMyUserId, recordInteraction, fetchInteractions } from "@/lib/api";
import {
  loadPostState,
  savePostState,
  loadFollows,
  saveFollows,
  syncToCloud,
} from "@/lib/sync";

const FEED_CAP = 216; // soft cap (~3 passes over the pin set) for the cycling feed
const USER_POSTS_KEY = "giftmaxxing_user_posts";

// Only surface posts with a real, hotlinkable photo. Drops Reddit preview.redd.it
// images (they 403 cross-origin), matching the bundled feed's photo-only quality.
const isPhoto = (p: Post) => !!p.product.image && !p.product.image.includes("redd.it");

// Persistence helpers for user-created posts.
function loadUserPosts(): Post[] {
  try {
    const raw = localStorage.getItem(USER_POSTS_KEY);
    return raw ? (JSON.parse(raw) as Post[]) : [];
  } catch {
    return [];
  }
}
function saveUserPosts(posts: Post[]): void {
  try {
    localStorage.setItem(USER_POSTS_KEY, JSON.stringify(posts));
  } catch { /* quota */ }
}
type ClaimState = Record<string, { claimedBy: string; claimedAt: number }>;
const CLAIMS_KEY = "giftmaxxing_claims";
function loadClaims(): ClaimState {
  try {
    const raw = localStorage.getItem(CLAIMS_KEY);
    return raw ? (JSON.parse(raw) as ClaimState) : {};
  } catch {
    return {};
  }
}
function saveClaims(state: ClaimState): void {
  try {
    localStorage.setItem(CLAIMS_KEY, JSON.stringify(state));
  } catch { /* quota */ }
}

type Store = {
  posts: Post[];
  follows: Set<string>;
  toggleLike: (postId: string) => void;
  toggleSave: (postId: string) => void;
  claimItem: (postId: string) => void;
  unclaimItem: (postId: string) => void;
  claims: ClaimState;
  reportSeen: (postId: string) => void;
  addComment: (postId: string, text: string) => void;
  replyAsMaxi: (postId: string, text: string) => void;
  addPost: (post: Post) => void;
  toggleFollow: (userId: string) => void;
  isFollowing: (userId: string) => boolean;
  // infinite scroll
  loadMore: () => void;
  hasMore: boolean;
  loadingMore: boolean;
  // overlays
  openPostId: string | null;
  openPost: (id: string | null) => void;
  storyIndex: number | null;
  openStory: (i: number | null) => void;
  // group chats
  groupChats: GroupChat[];
  openChatId: string | null;
  openChat: (id: string | null) => void;
  sendChatMessage: (chatId: string, text: string) => void;
  togglePinChat: (chatId: string) => void;
  togglePinMessage: (chatId: string, messageId: string) => void;
};

const Ctx = createContext<Store | null>(null);

export function useStore() {
  const v = useContext(Ctx);
  if (!v) throw new Error("useStore must be used within <AppStore>");
  return v;
}

export function AppStore({ children }: { children: React.ReactNode }) {
  // Taste derived from the onboarding profile, read once on mount. The feed tree
  // is client-only (it renders behind OnboardingGate, which shows a spinner on
  // the server), so localStorage is available here and there's no SSR/CSR
  // hydration mismatch. This biases the bundled feed toward what the user picked.
  const [taste, setTaste] = useState(() => tasteFromProfile(loadProfile()));
  // Live-feed facets from the profile (interests → vibes, genderPref →
  // recipient). Kept in a ref so fetch callbacks always see the latest without
  // re-creating them; bumping profileVersion re-runs the API takeover fetch.
  const feedFacetsRef = useRef(feedPersonalization(loadProfile()));
  const [profileVersion, setProfileVersion] = useState(0);
  // Feed is built from the bundled Pinterest pins (real photos), ordered by the
  // user's taste. Initialize synchronously so it's never blank on first paint.
  // Prepend persisted user posts so they always appear at the top.
  const [posts, setPosts] = useState<Post[]>(() => {
    const userPosts = loadUserPosts();
    const bundled = buildPinFeed(0, 12, taste);
    const state = loadPostState();
    const all = [...userPosts, ...bundled];
    return all.map((p) => {
      const s = state[p.id];
      if (!s) return p;
      return { ...p, liked: s.liked ?? p.liked, saved: s.saved ?? p.saved };
    });
  });
  const [follows, setFollows] = useState<Set<string>>(() => new Set(loadFollows()));
  const [openPostId, setOpenPostId] = useState<string | null>(null);
  const [storyIndex, setStoryIndex] = useState<number | null>(null);
  const [groupChats, setGroupChats] = useState<GroupChat[]>(GROUP_CHATS);
  const [openChatId, setOpenChatId] = useState<string | null>(null);
  const [hasMore, setHasMore] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const loadingRef = useRef(false); // guards against duplicate observer fires
  const seqRef = useRef(0); // makes appended feed item ids unique across cycles
  const offsetRef = useRef(12); // next flat offset into the cycling pin feed
  const apiModeRef = useRef(false); // true once the live API feed takes over
  const cursorRef = useRef<string | null>(null); // API feed pagination cursor

  // Pins repeat once we loop the set; give every appended item a unique id so
  // React keys + like/save stay correct.
  const appendUnique = useCallback(
    (list: Post[]) => list.map((p) => ({ ...p, id: `${p.id}~${seqRef.current++}` })),
    []
  );

  // Hydrate post state + follows when cloud data is restored by AccountSync.
  useEffect(() => {
    const restore = () => {
      const state = loadPostState();
      setPosts((prev) =>
        prev.map((p) => {
          const s = state[p.id];
          if (!s) return p;
          return { ...p, liked: s.liked ?? p.liked, saved: s.saved ?? p.saved };
        }),
      );
      setFollows(new Set(loadFollows()));
    };
    window.addEventListener("giftmaxxing:interactions-restored", restore);
    return () => window.removeEventListener("giftmaxxing:interactions-restored", restore);
  }, []);

  // The profile changed (onboarding finished, account switched, sign-out):
  // recompute taste + live-feed facets and refetch the personalized page.
  useEffect(() => {
    const onProfile = () => {
      const profile = loadProfile();
      setTaste(tasteFromProfile(profile));
      feedFacetsRef.current = feedPersonalization(profile);
      setProfileVersion((v) => v + 1);
    };
    window.addEventListener("giftmaxxing:profile", onProfile);
    return () => window.removeEventListener("giftmaxxing:profile", onProfile);
  }, []);

  // On mount, try the live API feed (real, scalable — paginated from DynamoDB via
  // the byFeed GSI). If it returns enough real-photo posts, it takes over from the
  // bundled pins; otherwise we keep the bundled feed so the app never goes blank.
  useEffect(() => {
    if (!isApiConfigured()) return;
    let cancelled = false;
    (async () => {
      try {
        const { posts: apiPosts, cursor } = await fetchFeed({
          limit: 16,
          userId: getMyUserId(),
          ...feedFacetsRef.current,
        });
        const photos = apiPosts.filter(isPhoto);
        if (!cancelled && photos.length >= 6) {
          apiModeRef.current = true;
          cursorRef.current = cursor;
          setHasMore(cursor != null);
          // Preserve user-created posts when the API feed takes over.
          // Re-apply persisted interaction state so likes/saves aren't lost
          // if the interaction-sync effect resolved before this one.
          setPosts((prev) => {
            const userPosts = prev.filter((p) => p.user === "you");
            const state = loadPostState();
            const merged = photos.map((p) => {
              const s = state[p.id];
              if (!s) return p;
              return { ...p, liked: s.liked ?? p.liked, saved: s.saved ?? p.saved };
            });
            return [...userPosts, ...merged];
          });
        }
      } catch {
        // keep the bundled feed on any error
      }
    })();
    return () => {
      cancelled = true;
    };
    // profileVersion: a changed profile (new account, onboarding done) must
    // re-pull the first page with the new facets — not keep the old feed.
  }, [profileVersion]);

  // On mount, fetch persisted interactions (likes/saves/comments) from the API to
  // restore cross-device state. Merges into posts AND into localStorage so the
  // local cache stays current. When the API isn't configured or unreachable, the
  // localStorage fallback (loadPostState) already handled state in the initializer.
  useEffect(() => {
    const userId = getMyUserId();
    if (!isApiConfigured() || !userId) return;
    let cancelled = false;
    (async () => {
      const items = await fetchInteractions(userId, ["like", "save", "comment"]);
      if (cancelled || !items || items.length === 0) return;

      // Build lookup maps from API interactions
      const likedSet = new Set<string>();
      const savedSet = new Set<string>();
      const commentsMap = new Map<string, { id: string; user: string; text: string }[]>();
      for (const it of items) {
        if (it.type === "like") likedSet.add(it.targetId);
        else if (it.type === "save") savedSet.add(it.targetId);
        else if (it.type === "comment" && it.data?.text) {
          const list = commentsMap.get(it.targetId) ?? [];
          list.push({ id: `c-api-${it.createdAt ?? Date.now()}`, user: "you", text: it.data.text });
          commentsMap.set(it.targetId, list);
        }
      }

      // Merge API state into posts
      setPosts((prev) =>
        prev.map((p) => {
          const isLiked = likedSet.has(p.id);
          const isSaved = savedSet.has(p.id);
          const apiComments = commentsMap.get(p.id);
          if (!isLiked && !isSaved && !apiComments) return p;
          const merged = { ...p };
          if (isLiked && !p.liked) { merged.liked = true; merged.likes = p.likes + 1; }
          if (isSaved && !p.saved) { merged.saved = true; }
          if (apiComments) {
            // Dedupe: only add API comments not already present locally
            const existingTexts = new Set(p.comments.map((c) => c.text));
            const newComments = apiComments.filter((c) => !existingTexts.has(c.text));
            if (newComments.length) merged.comments = [...p.comments, ...newComments];
          }
          return merged;
        })
      );

      // Sync to localStorage so it stays up-to-date with API state
      const state = loadPostState();
      for (const id of likedSet) state[id] = { ...state[id], liked: true };
      for (const id of savedSet) state[id] = { ...state[id], saved: true };
      savePostState(state);
    })();
    return () => { cancelled = true; };
  }, []);

  const toggleLike = useCallback((postId: string) => {
    setPosts((prev) => {
      const next = prev.map((p) => {
        if (p.id !== postId) return p;
        const liked = !p.liked;
        if (liked) recordInteraction(getMyUserId(), postId, "like");
        return { ...p, liked, likes: p.likes + (liked ? 1 : -1) };
      });
      const state = loadPostState();
      const target = next.find((p) => p.id === postId);
      if (target) {
        state[postId] = { ...state[postId], liked: target.liked };
        savePostState(state);
        syncToCloud();
      }
      return next;
    });
  }, []);

  const toggleSave = useCallback((postId: string) => {
    setPosts((prev) => {
      const next = prev.map((p) => {
        if (p.id !== postId) return p;
        const saved = !p.saved;
        if (saved) recordInteraction(getMyUserId(), postId, "save");
        return { ...p, saved };
      });
      const state = loadPostState();
      const target = next.find((p) => p.id === postId);
      if (target) {
        state[postId] = { ...state[postId], saved: target.saved };
        savePostState(state);
        syncToCloud();
      }
      return next;
    });
  }, []);

  const [claims, setClaims] = useState<ClaimState>(() => loadClaims());

  const claimItem = useCallback((postId: string) => {
    setClaims((prev) => {
      const next = { ...prev, [postId]: { claimedBy: "You", claimedAt: Date.now() } };
      saveClaims(next);
      return next;
    });
  }, []);

  const unclaimItem = useCallback((postId: string) => {
    setClaims((prev) => {
      const next = { ...prev };
      delete next[postId];
      saveClaims(next);
      return next;
    });
  }, []);

  // Mark a post seen once it's dwelled in view (called by PostCard's observer).
  // API mode only — bundled-pin ids aren't real backend postIds. recordInteraction
  // de-dupes per session, so repeated observer fires are cheap. This is what makes
  // the feed fresh: the backend excludes seen targets on the next load.
  const reportSeen = useCallback((postId: string) => {
    if (!apiModeRef.current) return;
    recordInteraction(getMyUserId(), postId, "seen");
  }, []);

  const addComment = useCallback((postId: string, text: string) => {
    const clean = text.trim();
    if (!clean) return;
    setPosts((prev) =>
      prev.map((p) =>
        p.id === postId
          ? {
              ...p,
              comments: [
                ...p.comments,
                { id: `c-${Date.now()}`, user: "you", text: clean },
              ],
            }
          : p
      )
    );
    recordInteraction(getMyUserId(), postId, "comment", { text: clean });
  }, []);

  // Append a reply authored by Maxi (the AI concierge) to a post's comment
  // thread — used when a user @mentions @maxi in a comment. No interaction is
  // recorded (it isn't a human action).
  const replyAsMaxi = useCallback((postId: string, text: string) => {
    const clean = text.trim();
    if (!clean) return;
    setPosts((prev) =>
      prev.map((p) =>
        p.id === postId
          ? {
              ...p,
              comments: [
                ...p.comments,
                { id: `c-maxi-${Date.now()}`, user: "maxi", text: clean },
              ],
            }
          : p
      )
    );
  }, []);

  const addPost = useCallback((post: Post) => {
    setPosts((prev) => [post, ...prev]);
    // Persist user-created posts so they survive page refreshes
    const existing = loadUserPosts();
    saveUserPosts([post, ...existing]);
  }, []);

  const toggleFollow = useCallback((userId: string) => {
    setFollows((prev) => {
      const next = new Set(prev);
      if (next.has(userId)) next.delete(userId);
      else next.add(userId);
      saveFollows([...next]);
      syncToCloud();
      return next;
    });
  }, []);

  const isFollowing = useCallback((u: string) => follows.has(u), [follows]);

  const sendChatMessage = useCallback((chatId: string, text: string) => {
    const clean = text.trim();
    if (!clean) return;
    setGroupChats((prev) =>
      prev.map((c) =>
        c.id === chatId
          ? {
              ...c,
              messages: [
                ...c.messages,
                { id: `cm-${Date.now()}`, user: "you", text: clean, time: "now" },
              ],
            }
          : c
      )
    );
  }, []);

  const togglePinChat = useCallback((chatId: string) => {
    setGroupChats((prev) =>
      prev.map((c) => (c.id === chatId ? { ...c, pinned: !c.pinned } : c))
    );
  }, []);

  const togglePinMessage = useCallback((chatId: string, messageId: string) => {
    setGroupChats((prev) =>
      prev.map((c) =>
        c.id === chatId
          ? {
              ...c,
              messages: c.messages.map((m) =>
                m.id === messageId ? { ...m, pinned: !m.pinned } : m
              ),
            }
          : c
      )
    );
  }, []);

  const loadMore = useCallback(() => {
    if (loadingRef.current || !hasMore) return;
    loadingRef.current = true;
    setLoadingMore(true);

    // API mode: page the live feed via the cursor, de-duping by id.
    if (apiModeRef.current) {
      (async () => {
        try {
          const { posts: apiPosts, cursor } = await fetchFeed({
            limit: 12,
            cursor: cursorRef.current,
            userId: getMyUserId(),
            ...feedFacetsRef.current,
          });
          cursorRef.current = cursor;
          const photos = apiPosts.filter(isPhoto);
          setPosts((prev) => {
            const seen = new Set(prev.map((p) => p.id));
            return [...prev, ...photos.filter((p) => !seen.has(p.id))];
          });
          setHasMore(cursor != null);
        } catch {
          setHasMore(false);
        } finally {
          setLoadingMore(false);
          loadingRef.current = false;
        }
      })();
      return;
    }

    // Bundled fallback: append the next cycled page after a brief skeleton flash.
    setTimeout(() => {
      setPosts((prev) => {
        if (prev.length >= FEED_CAP) {
          setHasMore(false);
          return prev;
        }
        const next = appendUnique(buildPinFeed(offsetRef.current, 8, taste));
        offsetRef.current += 8;
        return [...prev, ...next];
      });
      setLoadingMore(false);
      loadingRef.current = false;
    }, 450);
  }, [hasMore, appendUnique, taste]);

  const value = useMemo<Store>(
    () => ({
      posts,
      follows,
      toggleLike,
      toggleSave,
      claimItem,
      unclaimItem,
      claims,
      reportSeen,
      addComment,
      replyAsMaxi,
      addPost,
      toggleFollow,
      isFollowing,
      loadMore,
      hasMore,
      loadingMore,
      openPostId,
      openPost: setOpenPostId,
      storyIndex,
      openStory: setStoryIndex,
      groupChats,
      openChatId,
      openChat: setOpenChatId,
      sendChatMessage,
      togglePinChat,
      togglePinMessage,
    }),
    [posts, follows, toggleLike, toggleSave, claimItem, unclaimItem, claims, reportSeen, addComment, replyAsMaxi, addPost, toggleFollow, isFollowing, loadMore, hasMore, loadingMore, openPostId, storyIndex, groupChats, openChatId, sendChatMessage, togglePinChat, togglePinMessage]
  );

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}
