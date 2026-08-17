"use client";

import { useEffect, useRef, useState } from "react";
import { GRADIENTS } from "@/lib/data";
import { hiResImage } from "@/lib/images";
import { resolveUser, commentCountOf, type Post } from "@/lib/social";
import { useCurrentUser, displayUser } from "@/lib/identity";
import { Icons } from "@/components/ui";
import { useStore } from "@/components/app/store";
import { useMaxi } from "@/components/app/maxi-provider";
import { relativeTime } from "@/lib/api";

function BrandMark({ brand }: { brand: string }) {
  const label = brand.trim() || "Shop";
  const domain = label.toLowerCase().replace(/[^a-z0-9]+/g, "") + ".com";
  return (
    <span className="grid h-9 w-9 shrink-0 place-items-center overflow-hidden rounded-full border border-line bg-white text-[10px] font-bold text-ink-soft">
      {/* Brand favicon gives retailer posts a recognizable mark when available. */}
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={`https://www.google.com/s2/favicons?domain=${domain}&sz=64`}
        alt=""
        className="h-5 w-5"
        onError={(event) => {
          event.currentTarget.style.display = "none";
          event.currentTarget.parentElement!.textContent = label.slice(0, 2).toUpperCase();
        }}
      />
    </span>
  );
}

export function PostCard({ post }: { post: Post }) {
  const { toggleLike, toggleSave, addComment, replyAsMaxi, toggleFollow, isFollowing, openPost, reportSeen } = useStore();
  const { commentReply } = useMaxi();
  const me = useCurrentUser();
  const u = post.user === "you" ? me : resolveUser(post);
  const commentTotal = commentCountOf(post);
  const [draft, setDraft] = useState("");
  const [burst, setBurst] = useState(false);
  const [galleryIndex, setGalleryIndex] = useState(0);
  const [failedImages, setFailedImages] = useState<Set<string>>(() => new Set());
  const lastTap = useRef(0);
  const articleRef = useRef<HTMLElement>(null);
  const mediaRef = useRef<HTMLDivElement>(null);
  const allImages = [...new Set([post.product.image, ...(post.product.images ?? [])].filter(Boolean) as string[])];
  const gallery = allImages.filter((image) => !failedImages.has(image));

  // Report an impression once the card has dwelled in view (~50% visible for
  // 800ms). The store forwards it to the backend, which then excludes this item
  // from the next feed load — the "don't show me what I've already seen" loop.
  // Fires at most once per card; recordInteraction also de-dupes per session.
  useEffect(() => {
    const el = articleRef.current;
    if (!el || typeof IntersectionObserver === "undefined") return;
    let timer: ReturnType<typeof setTimeout> | null = null;
    const io = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          if (!timer)
            timer = setTimeout(() => {
              reportSeen(post.id);
              io.disconnect();
            }, 800);
        } else if (timer) {
          clearTimeout(timer);
          timer = null;
        }
      },
      { threshold: 0.5 }
    );
    io.observe(el);
    return () => {
      if (timer) clearTimeout(timer);
      io.disconnect();
    };
  }, [post.id, reportSeen]);

  const doubleTapLike = () => {
    if (!post.liked) toggleLike(post.id);
    setBurst(true);
    setTimeout(() => setBurst(false), 700);
  };

  const onMediaClick = () => {
    const now = Date.now();
    if (now - lastTap.current < 300) doubleTapLike();
    lastTap.current = now;
  };

  // A broken gallery slide is skipped; hide the card only when every remote
  // image failed.
  if (allImages.length > 0 && gallery.length === 0) return null;

  return (
    <article ref={articleRef} className="overflow-hidden rounded-2xl border border-line bg-surface shadow-sm">
      {/* header */}
      <div className="flex items-center gap-3 px-4 py-3">
        <BrandMark brand={post.product.brand} />
        <div className="leading-tight">
          <p className="text-sm font-bold text-ink">{post.product.brand || post.source || "Shop"}</p>
          {post.rec ? (
            <p className="flex items-center gap-1 text-xs text-coral">
              <Icons.sparkle size={12} />
              <span className="font-semibold">Suggested</span>
              <span className="text-ink-faint">· {post.reason}</span>
            </p>
          ) : (
            <p className="text-xs text-ink-faint">
              {relativeTime(post.createdAt) || "recently"}
            </p>
          )}
        </div>
        {post.user !== "you" && (
          <button
            onClick={() => toggleFollow(u.id)}
            className={`ml-auto text-sm font-bold ${
              isFollowing(u.id) ? "text-ink-soft" : "text-coral"
            }`}
          >
            {isFollowing(u.id) ? "Following" : "Follow"}
          </button>
        )}
        <button className={`text-ink-soft ${post.user !== "you" ? "ml-3" : "ml-auto"}`}>
          <Icons.more size={20} />
        </button>
      </div>

      {/* media */}
      <div
        className="relative grid aspect-square w-full cursor-pointer select-none place-items-center"
        style={{ background: GRADIENTS[post.product.grad] }}
        onClick={onMediaClick}
      >
        {gallery.length ? (
          <div
            ref={mediaRef}
            className="absolute inset-0 flex snap-x snap-mandatory overflow-x-auto [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
            onScroll={(event) => {
              const width = event.currentTarget.clientWidth;
              if (width) setGalleryIndex(Math.round(event.currentTarget.scrollLeft / width));
            }}
          >
            {gallery.map((image, index) => (
              <div key={image} className="relative min-w-full snap-center">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={hiResImage(image)}
                  alt={`${post.product.name} — image ${index + 1}`}
                  loading="lazy"
                  className="h-full w-full object-cover"
                  onError={() => setFailedImages((failed) => new Set(failed).add(image))}
                />
              </div>
            ))}
          </div>
        ) : (
          <span className="text-[96px]">{post.product.emoji}</span>
        )}

        {gallery.length > 1 && (
          <>
            <span className="absolute right-3 top-3 rounded-full bg-black/60 px-2.5 py-1 text-xs font-semibold text-white">
              {Math.min(galleryIndex + 1, gallery.length)}/{gallery.length}
            </span>
            {galleryIndex > 0 && (
              <button
                aria-label="Previous image"
                className="absolute left-2 grid h-8 w-8 place-items-center rounded-full bg-black/45 text-2xl text-white"
                onClick={(event) => {
                  event.stopPropagation();
                  mediaRef.current?.scrollTo({ left: (galleryIndex - 1) * mediaRef.current.clientWidth, behavior: "smooth" });
                }}
              >
                ‹
              </button>
            )}
            {galleryIndex < gallery.length - 1 && (
              <button
                aria-label="Next image"
                className="absolute right-2 grid h-8 w-8 place-items-center rounded-full bg-black/45 text-2xl text-white"
                onClick={(event) => {
                  event.stopPropagation();
                  mediaRef.current?.scrollTo({ left: (galleryIndex + 1) * mediaRef.current.clientWidth, behavior: "smooth" });
                }}
              >
                ›
              </button>
            )}
          </>
        )}

        {/* product tag chip */}
        <button
          onClick={(e) => {
            e.stopPropagation();
            openPost(post.id);
          }}
          className="absolute bottom-3 left-3 flex items-center gap-2 rounded-full bg-black/55 px-3 py-1.5 text-xs font-semibold text-white backdrop-blur"
        >
          <Icons.gift size={14} /> {post.product.name}
          {post.product.price > 0 ? ` · $${post.product.price}` : ""}
        </button>

        {burst && (
          <span className="pointer-events-none absolute animate-[rise_0.7s_ease] text-white drop-shadow-lg">
            <Icons.heartFill size={110} />
          </span>
        )}
      </div>

      {/* actions */}
      <div className="flex items-center gap-4 px-4 pt-3 text-ink">
        <button onClick={() => toggleLike(post.id)} className={post.liked ? "text-coral" : ""} aria-label="Like">
          {post.liked ? <Icons.heartFill size={26} /> : <Icons.heart size={26} />}
        </button>
        <button onClick={() => openPost(post.id)} aria-label="Comment">
          <Icons.comment size={25} />
        </button>
        <button
          onClick={() => {
            const url = `${window.location.origin}/feed`;
            const priceTag = post.product.price > 0 ? ` ($${post.product.price})` : "";
            const text = `Check out this find: ${post.product.name}${priceTag} on Giftmaxxing`;
            if (navigator.share) {
              navigator.share({ title: "Giftmaxxing", text, url }).catch(() => {});
            } else {
              navigator.clipboard.writeText(`${text} — ${url}`).catch(() => {});
            }
          }}
          aria-label="Share"
        >
          <Icons.share size={24} />
        </button>
        <button
          onClick={() => toggleSave(post.id)}
          className={`ml-auto ${post.saved ? "text-ink" : ""}`}
          aria-label="Save"
        >
          {post.saved ? <Icons.bookmarkFill size={25} /> : <Icons.bookmark size={25} />}
        </button>
      </div>

      {/* likes + caption + comments */}
      <div className="px-4 pb-4 pt-2">
        <p className="text-sm font-bold text-ink">{post.likes.toLocaleString()} likes</p>
        {post.caption && (
          <p className="mt-1 text-sm text-ink">
            <span className="font-bold">{u.handle}</span> {post.caption}
          </p>
        )}

        {commentTotal > 0 && (
          <button
            onClick={() => openPost(post.id)}
            className="mt-1.5 block text-sm text-ink-faint"
          >
            View all {commentTotal.toLocaleString()} comments
          </button>
        )}
        {post.comments.slice(-2).map((c) => (
          <p key={c.id} className="mt-1 text-sm text-ink">
            <span className="font-bold">{displayUser(c.user, me).handle}</span> {c.text}
          </p>
        ))}

        {/* add comment */}
        <form
          onSubmit={(e) => {
            e.preventDefault();
            const text = draft.trim();
            if (!text) return;
            addComment(post.id, text);
            if (/@maxi\b/i.test(text)) {
              const query = text.replace(/@maxi\b/i, "").trim() || `any gift ideas like ${post.product.name}?`;
              // Maxi replies inline in the thread (does NOT open the side panel).
              void commentReply(query, post.product.name).then((reply) => replyAsMaxi(post.id, reply));
            }
            setDraft("");
          }}
          className="mt-3 flex items-center gap-2 border-t border-line pt-3"
        >
          <input
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            placeholder="Add a comment…  (try @maxi)"
            className="flex-1 bg-transparent text-sm text-ink placeholder:text-ink-faint outline-none"
          />
          {draft.trim() && (
            <button type="submit" className="text-sm font-bold text-coral">
              Post
            </button>
          )}
        </form>
      </div>
    </article>
  );
}
