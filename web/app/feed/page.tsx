"use client";

import { Fragment, type TouchEvent, useEffect, useRef, useState } from "react";
import { StoriesTray } from "@/components/app/stories";
import { PostCard } from "@/components/app/post-card";
import { RightRail } from "@/components/app/right-rail";
import { FeedPoolCard } from "@/components/app/feed-pool-card";
import { EventBanner } from "@/components/app/event-banner";
import { GiftPromptCards } from "@/components/app/gift-prompt-card";
import { ConsultCta } from "@/components/app/consult-cta";
import { MilestoneBanner } from "@/components/app/milestone-banner";
import { useStore } from "@/components/app/store";
import { type Fundraiser, loadFundraisers } from "@/lib/fundraisers";

export default function FeedPage() {
  const { posts, loadMore, refreshFeed, hasMore, loadingMore, refreshing } = useStore();
  const sentinelRef = useRef<HTMLDivElement | null>(null);
  const touchStartY = useRef<number | null>(null);
  const [pullDistance, setPullDistance] = useState(0);
  const [pools, setPools] = useState<Fundraiser[]>([]);
  const feedPools = pools.slice(0, 3);

  const onTouchStart = (event: TouchEvent<HTMLDivElement>) => {
    if (window.scrollY === 0) touchStartY.current = event.touches[0].clientY;
  };
  const onTouchMove = (event: TouchEvent<HTMLDivElement>) => {
    if (touchStartY.current === null || refreshing) return;
    const distance = event.touches[0].clientY - touchStartY.current;
    if (distance > 0) setPullDistance(Math.min(distance, 96));
  };
  const onTouchEnd = async () => {
    if (touchStartY.current === null) return;
    touchStartY.current = null;
    if (pullDistance >= 64) await refreshFeed();
    setPullDistance(0);
  };

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setPools(loadFundraisers());
  }, []);

  // Infinite scroll: when the sentinel near the bottom enters view, fetch the
  // next ranked page from the recommendation engine.
  useEffect(() => {
    const el = sentinelRef.current;
    if (!el || !hasMore || loadingMore || posts.length === 0) return;
    const io = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting) loadMore();
      },
      { rootMargin: "600px 0px" } // prefetch before the user hits the end
    );
    io.observe(el);
    return () => io.disconnect();
  }, [loadMore, hasMore, loadingMore, posts.length]);

  return (
    <div
      className="mx-auto flex max-w-5xl justify-center gap-12 px-3 py-6 sm:px-5"
      onTouchStart={onTouchStart}
      onTouchMove={onTouchMove}
      onTouchEnd={onTouchEnd}
    >
      <div className="w-full max-w-[470px] space-y-5">
        {(refreshing || pullDistance > 0) && (
          <div className="-mb-2 flex h-6 items-center justify-center text-xs font-semibold text-ink-faint" aria-live="polite">
            {refreshing ? "Refreshing feed…" : pullDistance >= 64 ? "Release to refresh" : "Pull to refresh"}
          </div>
        )}
        <EventBanner />
        <GiftPromptCards />
        <ConsultCta />
        <MilestoneBanner />
        <StoriesTray />

        {posts.map((p, i) => (
          <Fragment key={p.id}>
            <PostCard post={p} />
            {feedPools.length > 0 && (i + 1) % 5 === 0 && (
              <FeedPoolCard f={feedPools[Math.floor(i / 5) % feedPools.length]} />
            )}
          </Fragment>
        ))}

        {loadingMore && (
          <>
            <PostSkeleton />
            <PostSkeleton />
          </>
        )}

        {/* sentinel */}
        {hasMore ? (
          <div ref={sentinelRef} className="h-10" aria-hidden />
        ) : (
          <p className="py-8 text-center text-sm text-ink-faint">
            You&apos;re all caught up ✨
          </p>
        )}
      </div>
      <RightRail />
    </div>
  );
}

function PostSkeleton() {
  return (
    <div className="overflow-hidden rounded-2xl border border-line bg-surface">
      <div className="flex items-center gap-3 px-4 py-3">
        <div className="h-9 w-9 animate-pulse rounded-full bg-line" />
        <div className="space-y-1.5">
          <div className="h-2.5 w-24 animate-pulse rounded bg-line" />
          <div className="h-2 w-16 animate-pulse rounded bg-line" />
        </div>
      </div>
      <div className="aspect-square w-full animate-pulse bg-line" />
      <div className="space-y-2 px-4 py-4">
        <div className="h-2.5 w-32 animate-pulse rounded bg-line" />
        <div className="h-2.5 w-48 animate-pulse rounded bg-line" />
      </div>
    </div>
  );
}
