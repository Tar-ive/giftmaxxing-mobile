// Social graph + feed content for the Instagram-style app experience.
import { PRODUCTS, type Grad, type Product } from "@/lib/data";

export type User = {
  id: string;
  name: string;
  handle: string;
  grad: Grad;
  bio?: string;
  followers?: number;
  following?: number;
};

export const USERS: Record<string, User> = {
  you: { id: "you", name: "You", handle: "you", grad: "coral" },
  maxi: { id: "maxi", name: "Maxi", handle: "maxi", grad: "coral", bio: "your AI gift concierge 🎁" },
  maya: { id: "maya", name: "Maya Reyes", handle: "mayareyes", grad: "rose", bio: "film photos + cozy corners 📷", followers: 1840, following: 412 },
  jules: { id: "jules", name: "Jules Park", handle: "julesp", grad: "lilac", bio: "professional group-gift organizer (unpaid)", followers: 980, following: 530 },
  sam: { id: "sam", name: "Sam Okafor", handle: "samok", grad: "sky", bio: "off to Lisbon 🛫", followers: 642, following: 388 },
  noor: { id: "noor", name: "Noor Haddad", handle: "noorh", grad: "butter", bio: "apartment plants & candles", followers: 1220, following: 301 },
  theo: { id: "theo", name: "Theo Lin", handle: "theolin", grad: "sage", bio: "vinyl hoarder", followers: 2310, following: 190 },
  ivy: { id: "ivy", name: "Ivy Castellano", handle: "ivycast", grad: "rose", bio: "warm tones only", followers: 1530, following: 470 },
  remy: { id: "remy", name: "Remy Adebayo", handle: "remyy", grad: "peach", bio: "new apartment, who dis", followers: 760, following: 540 },
};

const P = (id: string): Product => PRODUCTS.find((p) => p.id === id)!;

export type Comment = { id: string; user: string; text: string };

export type Post = {
  id: string;
  user: string;
  createdAt?: number;
  time: string;
  product: Product;
  caption: string;
  likes: number;
  liked: boolean;
  saved: boolean;
  comments: Comment[];
  commentCount?: number; // server-provided count when comments aren't hydrated
  source?: string;
  url?: string; // permalink to the original post (Reddit-sourced)
  productUrl?: string | null; // off-site product link
  rec?: boolean; // surfaced by the recommendation engine
  reason?: string; // human-readable "why you're seeing this"
  category?: string; // catalog category facet (drives the gift-consult ranking)
};

export const POSTS: Post[] = [
  {
    id: "p1",
    user: "maya",
    time: "12m",
    product: P("camera"),
    caption:
      "genuinely the move for anyone turning 22. point-and-shoot szn is back 📸",
    likes: 214,
    liked: false,
    saved: false,
    comments: [
      { id: "c1", user: "jules", text: "adding to my list immediately" },
      { id: "c2", user: "theo", text: "the film aesthetic >>>" },
    ],
  },
  {
    id: "p2",
    user: "theo",
    time: "1h",
    product: P("vinyl"),
    caption:
      "found Ivy's most-played record on her linked Spotify. she has no idea 🤫",
    likes: 88,
    liked: true,
    saved: false,
    source: "Spotify",
    comments: [{ id: "c3", user: "noor", text: "stealth gifting unlocked" }],
  },
  {
    id: "p3",
    user: "jules",
    time: "4h",
    product: P("perfume"),
    caption:
      "price dropped 20% — Maxi pinged me the second it did. snagged it for mom 💐",
    likes: 156,
    liked: false,
    saved: true,
    comments: [],
  },
  {
    id: "p4",
    user: "noor",
    time: "6h",
    product: P("candle"),
    caption: "apartment warming season. fig & oud is THE scent 🕯️",
    likes: 73,
    liked: false,
    saved: false,
    comments: [
      { id: "c4", user: "remy", text: "need this for the new place" },
      { id: "c5", user: "ivy", text: "obsessed" },
    ],
  },
  {
    id: "p5",
    user: "ivy",
    time: "9h",
    product: P("lamp"),
    caption: "sunset on demand. warm tones only in this household 🌅",
    likes: 142,
    liked: false,
    saved: false,
    comments: [{ id: "c6", user: "maya", text: "the GLOW" }],
  },
  {
    id: "p6",
    user: "sam",
    time: "1d",
    product: P("buds"),
    caption: "packing light for Lisbon but these are coming with me 🎧",
    likes: 201,
    liked: true,
    saved: false,
    comments: [],
  },
];

export type Story = {
  id: string;
  user: string;
  label: string;
  countdown?: string;
  add?: boolean;
  live?: boolean;
  kind?: string;
};

export const STORIES: Story[] = [
  { id: "s_you", user: "you", label: "Your story", add: true },
  { id: "s_drop", user: "you", label: "Drops", live: true, kind: "drop" },
  { id: "s_maya", user: "maya", label: "Maya · 4d", countdown: "4d", kind: "birthday" },
  { id: "s_sam", user: "sam", label: "Sam farewell", kind: "event" },
  { id: "s_noor", user: "noor", label: "Noor · 11d", countdown: "11d", kind: "birthday" },
  { id: "s_theo", user: "theo", label: "Theo", kind: "list" },
  { id: "s_ivy", user: "ivy", label: "Ivy · 18d", countdown: "18d", kind: "anniv" },
  { id: "s_remy", user: "remy", label: "Remy", kind: "event" },
];

// Group chats for coordinating gifts (replaces stories in the tray).
export type ChatMessage = {
  id: string;
  user: string;
  text: string;
  time: string;
  pinned?: boolean;
};

export type GroupChat = {
  id: string;
  forUser: string; // who the gift is for
  occasion?: string;
  countdown?: string;
  members: string[]; // user ids participating
  messages: ChatMessage[];
  pinned: boolean; // whether the chat is pinned to the tray
  newChat?: boolean; // "start a new group chat" placeholder
};

export const GROUP_CHATS: GroupChat[] = [
  {
    id: "gc_new",
    forUser: "you",
    occasion: "new",
    members: [],
    messages: [],
    pinned: false,
    newChat: true,
  },
  {
    id: "gc_maya",
    forUser: "maya",
    occasion: "birthday",
    countdown: "4d",
    members: ["you", "jules", "noor", "sam"],
    pinned: true,
    messages: [
      { id: "m1", user: "jules", text: "Should we pool for that camera she's been eyeing?", time: "2h", pinned: true },
      { id: "m2", user: "noor", text: "Yes! I can chip in $30", time: "1h" },
      { id: "m3", user: "sam", text: "Count me in. What's the total?", time: "45m" },
      { id: "m4", user: "you", text: "It's $89. If we split 4 ways that's ~$22 each", time: "30m", pinned: true },
      { id: "m5", user: "jules", text: "Perfect. I'll order it tonight", time: "12m" },
    ],
  },
  {
    id: "gc_sam",
    forUser: "sam",
    occasion: "farewell",
    members: ["you", "maya", "jules", "theo"],
    pinned: true,
    messages: [
      { id: "m6", user: "maya", text: "Sam's going to Lisbon! Should we get him something travel-related?", time: "1d", pinned: true },
      { id: "m7", user: "theo", text: "What about those noise-cancelling buds he wanted?", time: "1d" },
      { id: "m8", user: "you", text: "Good idea. Or a travel journal?", time: "22h" },
      { id: "m9", user: "jules", text: "Let's do both! Travel journal + a nice pen", time: "20h" },
    ],
  },
  {
    id: "gc_noor",
    forUser: "noor",
    occasion: "birthday",
    countdown: "11d",
    members: ["you", "maya", "remy"],
    pinned: false,
    messages: [
      { id: "m10", user: "maya", text: "Noor's birthday is coming up. She's really into plants lately", time: "3d" },
      { id: "m11", user: "remy", text: "I saw this amazing terrarium kit for $45", time: "2d", pinned: true },
      { id: "m12", user: "you", text: "That's perfect for her apartment!", time: "1d" },
    ],
  },
  {
    id: "gc_ivy",
    forUser: "ivy",
    occasion: "anniversary",
    countdown: "18d",
    members: ["you", "theo", "maya"],
    pinned: false,
    messages: [
      { id: "m13", user: "theo", text: "Ivy and Alex's anniversary is in 18 days", time: "5d" },
      { id: "m14", user: "maya", text: "She loves warm tones. What about that sunset lamp?", time: "4d" },
      { id: "m15", user: "you", text: "Great call. I'll check the price", time: "3d" },
    ],
  },
  {
    id: "gc_theo",
    forUser: "theo",
    occasion: "just because",
    members: ["you", "ivy", "maya"],
    pinned: false,
    messages: [
      { id: "m16", user: "ivy", text: "Found a rare pressing of Theo's favorite album", time: "2d", pinned: true },
      { id: "m17", user: "maya", text: "He would LOVE that. How much?", time: "1d" },
    ],
  },
  {
    id: "gc_remy",
    forUser: "remy",
    occasion: "housewarming",
    members: ["you", "noor", "jules"],
    pinned: false,
    messages: [
      { id: "m18", user: "noor", text: "Remy just moved! We should get a housewarming gift", time: "6h" },
      { id: "m19", user: "jules", text: "What about a nice candle set?", time: "3h" },
    ],
  },
];

export type Suggestion = { user: string; reason: string };
export const SUGGESTIONS: Suggestion[] = [
  { user: "remy", reason: "Followed by jules + 3 more" },
  { user: "ivy", reason: "Suggested for you" },
  { user: "theo", reason: "Followed by maya" },
  { user: "noor", reason: "New to Giftmaxxing" },
  { user: "sam", reason: "Followed by jules" },
];

// Resolve a display user for a post. Static demo users live in USERS; Reddit-
// sourced posts (author = "reddit_<sub>") synthesize one from the post source.
export function resolveUser(post: Post): User {
  const known = USERS[post.user];
  if (known) return known;
  const handle = (post.source ?? post.user ?? "reddit").replace(/^r\//, "");
  return {
    id: post.user,
    name: post.source ?? "Reddit",
    handle,
    grad: post.product.grad,
  };
}

// Number of comments to display for a post (handles server count or hydrated list).
export function commentCountOf(post: Post): number {
  return post.commentCount ?? post.comments.length;
}

// Products shown on a profile grid (their posted finds + curated)
export function profilePosts(userId: string): Post[] {
  const own = POSTS.filter((p) => p.user === userId);
  if (own.length >= 6) return own;
  // pad the grid with curated finds so every profile looks populated
  const extras = PRODUCTS.filter((p) => !own.some((o) => o.product.id === p.id))
    .slice(0, 9 - own.length)
    .map((product, i) => ({
      id: `${userId}-x${i}`,
      user: userId,
      time: "2d",
      product,
      caption: "",
      likes: 40 + i * 7,
      liked: false,
      saved: false,
      comments: [],
    }));
  return [...own, ...extras];
}
