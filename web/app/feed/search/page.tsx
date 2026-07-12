"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { USERS } from "@/lib/social";
import { PINS, type Pin } from "@/lib/pins";
import { isApiConfigured, getMyUserId } from "@/lib/api";
import { visualSearch } from "@/lib/visual-search";
import { enrichBrand } from "@/lib/brand-enrichment";
import { Avatar, Icons } from "@/components/ui";
import { ItemDetailModal } from "@/components/app/item-detail-modal";
import {
  type SearchCard,
  cardToPin,
  pinToCard,
  visualToCard,
  CardGrid,
  EmptyNote,
} from "@/components/app/explore-search";
import {
  FRIENDS_EVENT,
  getFriendshipStatus,
  requestFriend,
  searchPeople,
  type PublicPerson,
} from "@/lib/friends";

type SearchTab = "people" | "products" | "brands" | "visual";

export default function SearchPage() {
  const [q, setQ] = useState("");
  const [tab, setTab] = useState<SearchTab>("people");
  const [vResults, setVResults] = useState<SearchCard[] | null>(null);
  const [vLoading, setVLoading] = useState(false);
  const [vError, setVError] = useState<string | null>(null);
  const [queryImage, setQueryImage] = useState<string | null>(null);
  const [selectedPin, setSelectedPin] = useState<Pin | null>(null);
  const [people, setPeople] = useState<PublicPerson[]>([]);
  const [friendStatus, setFriendStatus] = useState<
    Record<string, "none" | "pending" | "accepted">
  >({});
  const [busyId, setBusyId] = useState<string | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);
  const myId = getMyUserId() ?? "you";

  const selectItem = (card: SearchCard) => setSelectedPin(cardToPin(card));

  useEffect(() => {
    if (!queryImage) return;
    return () => URL.revokeObjectURL(queryImage);
  }, [queryImage]);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const items = await searchPeople(q, 30);
      if (cancelled) return;
      setPeople(items.filter((p) => p.userId !== myId));
    })();
    return () => {
      cancelled = true;
    };
  }, [q, myId]);

  useEffect(() => {
    if (tab !== "people" || !people.length) return;
    let cancelled = false;
    (async () => {
      const entries = await Promise.all(
        people.map(async (p) => {
          const s = await getFriendshipStatus(myId, p.userId);
          return [p.userId, s.status] as const;
        })
      );
      if (cancelled) return;
      setFriendStatus(Object.fromEntries(entries));
    })();
    const on = () => {
      void (async () => {
        const entries = await Promise.all(
          people.map(async (p) => {
            const s = await getFriendshipStatus(myId, p.userId);
            return [p.userId, s.status] as const;
          })
        );
        setFriendStatus(Object.fromEntries(entries));
      })();
    };
    window.addEventListener(FRIENDS_EVENT, on);
    return () => {
      cancelled = true;
      window.removeEventListener(FRIENDS_EVENT, on);
    };
  }, [people, myId, tab]);

  const products = useMemo(() => {
    const t = q.trim().toLowerCase();
    if (!t) return PINS.slice(0, 18).map(pinToCard);
    return PINS.filter(
      (p) =>
        p.title.toLowerCase().includes(t) ||
        p.category.toLowerCase().includes(t) ||
        enrichBrand(p).toLowerCase().includes(t)
    ).map(pinToCard);
  }, [q]);

  const brands = useMemo(() => {
    const t = q.trim().toLowerCase();
    const brandMap = new Map<string, SearchCard[]>();
    for (const p of PINS) {
      const brand = enrichBrand(p);
      if (t && !brand.toLowerCase().includes(t)) continue;
      const key = brand.toLowerCase();
      if (!brandMap.has(key)) brandMap.set(key, []);
      brandMap.get(key)!.push({ ...pinToCard(p), brand });
    }
    return Array.from(brandMap.entries())
      .sort((a, b) => b[1].length - a[1].length)
      .slice(0, 20);
  }, [q]);

  function clearVisual() {
    setQueryImage(null);
    setVResults(null);
    setVError(null);
    setVLoading(false);
  }

  async function runVisualSearch(file: File) {
    setTab("visual");
    setQueryImage(URL.createObjectURL(file));
    setVResults(null);
    setVError(null);
    setVLoading(true);
    try {
      if (!isApiConfigured()) {
        setVError("Visual search runs on the live AWS API — set NEXT_PUBLIC_API_URL to enable it.");
        return;
      }
      const results = await visualSearch(file, { limit: 18 });
      setVResults(results.map(visualToCard));
    } catch {
      setVError("Couldn't run visual search. Try a different image.");
    } finally {
      setVLoading(false);
    }
  }

  function onFile(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (file) void runVisualSearch(file);
  }

  useEffect(() => {
    const onPaste = (e: ClipboardEvent) => {
      const file = Array.from(e.clipboardData?.files ?? []).find((f) =>
        f.type.startsWith("image/")
      );
      if (!file) return;
      e.preventDefault();
      void runVisualSearch(file);
    };
    document.addEventListener("paste", onPaste);
    return () => document.removeEventListener("paste", onPaste);
  }, []);

  const [dragOver, setDragOver] = useState(false);
  function onDrop(e: React.DragEvent) {
    e.preventDefault();
    setDragOver(false);
    const file = Array.from(e.dataTransfer?.files ?? []).find((f) =>
      f.type.startsWith("image/")
    );
    if (file) void runVisualSearch(file);
  }

  async function addFriend(p: PublicPerson) {
    setBusyId(p.userId);
    await requestFriend({
      fromUserId: myId,
      toUserId: p.userId,
      toName: p.name,
      toHandle: p.handle,
    });
    const s = await getFriendshipStatus(myId, p.userId);
    setFriendStatus((prev) => ({ ...prev, [p.userId]: s.status }));
    setBusyId(null);
  }

  const TABS: { key: SearchTab; label: string }[] = [
    { key: "people", label: "People" },
    { key: "brands", label: "Brands" },
    { key: "products", label: "Products" },
    { key: "visual", label: "Visual" },
  ];

  return (
    <div
      className={`mx-auto max-w-xl px-4 py-6 ${dragOver ? "rounded-3xl outline-2 outline-dashed outline-coral" : ""}`}
      onDragOver={(e) => {
        e.preventDefault();
        setDragOver(true);
      }}
      onDragLeave={() => setDragOver(false)}
      onDrop={onDrop}
    >
      <div className="mb-4 flex items-center gap-2 rounded-full border border-line bg-surface px-4 py-2.5">
        <Icons.search size={18} className="shrink-0 text-ink-faint" />
        <input
          autoFocus
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="Search people, brands, products…"
          className="min-w-0 flex-1 bg-transparent text-sm text-ink placeholder:text-ink-faint outline-none"
        />
        {(q || queryImage) && (
          <button
            onClick={() => {
              setQ("");
              clearVisual();
            }}
            aria-label="Clear search"
            className="shrink-0 text-ink-faint transition-colors hover:text-ink"
          >
            <Icons.close size={18} />
          </button>
        )}
        <span className="h-5 w-px shrink-0 bg-line" />
        <button
          onClick={() => fileRef.current?.click()}
          aria-label="Search by image"
          title="Search by image (visual search)"
          className="flex shrink-0 items-center gap-1.5 text-sm font-semibold text-ink-soft transition-colors hover:text-coral"
        >
          <Icons.camera size={20} />
          <span className="hidden sm:inline">Visual</span>
        </button>
        <input ref={fileRef} type="file" accept="image/*" hidden onChange={onFile} />
      </div>

      <div className="mb-5 flex gap-1 rounded-xl border border-line bg-cream p-1">
        {TABS.map((t) => (
          <button
            key={t.key}
            onClick={() => setTab(t.key)}
            className={`flex-1 rounded-lg px-3 py-2 text-sm font-semibold transition-colors ${
              tab === t.key ? "bg-surface text-ink shadow-sm" : "text-ink-soft hover:text-ink"
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>

      {tab === "people" && (
        <div className="space-y-1">
          <div className="mb-2 flex items-center justify-between px-1">
            <p className="text-sm font-bold text-ink-soft">{q ? "Results" : "Discover people"}</p>
            <Link href="/feed/friends" className="text-xs font-bold text-coral hover:underline">
              Friends hub →
            </Link>
          </div>
          {people.map((u) => {
            const st = friendStatus[u.userId] ?? "none";
            const grad = USERS[u.userId]?.grad ?? "coral";
            return (
              <div
                key={u.userId}
                className="flex items-center gap-3 rounded-xl px-2 py-2 hover:bg-ink/5"
              >
                <Link href={`/feed/${u.userId}`} className="flex min-w-0 flex-1 items-center gap-3">
                  <Avatar grad={grad} label={u.name} size={44} />
                  <div className="min-w-0">
                    <p className="truncate text-sm font-bold text-ink">@{u.handle}</p>
                    <p className="truncate text-xs text-ink-faint">{u.name}</p>
                    {u.interests && u.interests.length > 0 && (
                      <p className="truncate text-[11px] text-ink-soft">
                        {u.interests.slice(0, 3).join(" · ")}
                      </p>
                    )}
                  </div>
                </Link>
                {st === "accepted" ? (
                  <Link
                    href="/feed/messages"
                    className="shrink-0 rounded-full bg-ink px-3 py-1.5 text-xs font-bold text-cream"
                  >
                    Message
                  </Link>
                ) : st === "pending" ? (
                  <span className="shrink-0 text-xs font-semibold text-ink-faint">Requested</span>
                ) : (
                  <button
                    disabled={busyId === u.userId}
                    onClick={() => void addFriend(u)}
                    className="shrink-0 rounded-full bg-coral px-3 py-1.5 text-xs font-bold text-white"
                  >
                    Add friend
                  </button>
                )}
              </div>
            );
          })}
          {people.length === 0 && <EmptyNote>No people found.</EmptyNote>}
        </div>
      )}

      {tab === "products" && (
        <section>
          <p className="mb-3 px-1 text-sm font-bold text-ink-soft">
            {q
              ? `${products.length} result${products.length === 1 ? "" : "s"} for "${q.trim()}"`
              : "Trending products"}
          </p>
          {products.length > 0 ? (
            <CardGrid cards={products} onSelect={selectItem} />
          ) : (
            <EmptyNote>
              No products match &ldquo;{q.trim()}&rdquo;. Try a brand, category, or vibe.
            </EmptyNote>
          )}
        </section>
      )}

      {tab === "brands" && (
        <section>
          <p className="mb-3 px-1 text-sm font-bold text-ink-soft">
            {q ? `Brands matching "${q.trim()}"` : "All brands"}
          </p>
          {brands.length > 0 ? (
            <div className="space-y-5">
              {brands.map(([brand, cards]) => (
                <div key={brand}>
                  <p className="mb-2 text-sm font-bold capitalize text-ink">{brand}</p>
                  <CardGrid cards={cards.slice(0, 6)} onSelect={selectItem} />
                </div>
              ))}
            </div>
          ) : (
            <EmptyNote>No brands match &ldquo;{q.trim()}&rdquo;.</EmptyNote>
          )}
        </section>
      )}

      {tab === "visual" && (
        <section>
          {queryImage ? (
            <>
              <div className="mb-4 flex items-center gap-3">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={queryImage}
                  alt="Your search image"
                  className="h-14 w-14 shrink-0 rounded-xl border border-line object-cover"
                />
                <div className="min-w-0 flex-1">
                  <p className="font-display text-lg font-bold text-ink">Visually similar</p>
                  <p className="truncate text-sm text-ink-soft">
                    {vLoading
                      ? "Searching the catalog…"
                      : "Image → Titan embedding → S3 Vectors kNN"}
                  </p>
                </div>
                <button
                  onClick={clearVisual}
                  className="shrink-0 rounded-full border border-line px-3 py-1.5 text-sm font-semibold text-ink hover:bg-coral-soft"
                >
                  Clear
                </button>
              </div>

              {vLoading ? (
                <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
                  {Array.from({ length: 6 }).map((_, i) => (
                    <div key={i} className="aspect-square animate-pulse rounded-2xl bg-line" />
                  ))}
                </div>
              ) : vError ? (
                <EmptyNote>{vError}</EmptyNote>
              ) : vResults && vResults.length ? (
                <CardGrid cards={vResults} onSelect={selectItem} />
              ) : (
                <EmptyNote>No visually similar finds yet. Try another photo.</EmptyNote>
              )}
            </>
          ) : (
            <div className="flex flex-col items-center gap-4 py-12 text-center">
              <div className="grid h-16 w-16 place-items-center rounded-2xl bg-coral-soft">
                <Icons.camera size={32} className="text-coral" />
              </div>
              <div>
                <p className="font-display text-lg font-bold text-ink">Search by image</p>
                <p className="mt-1 text-sm text-ink-soft">
                  Saw it on Instagram or Pinterest? Screenshot it, then upload, paste (⌘V), or
                  drop the photo here — we&rsquo;ll find visually similar gifts you can actually
                  buy.
                </p>
              </div>
              <button
                onClick={() => fileRef.current?.click()}
                className="rounded-full bg-coral px-6 py-2.5 text-sm font-bold text-white transition-opacity hover:opacity-90"
              >
                Upload image
              </button>
            </div>
          )}
        </section>
      )}

      <ItemDetailModal pin={selectedPin} onClose={() => setSelectedPin(null)} />
    </div>
  );
}
