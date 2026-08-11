"use client";

import { useRef, useState } from "react";
import { GRADIENTS } from "@/lib/data";
import { productAmazonUrl, AFFILIATE_REL } from "@/lib/affiliate";
import { hiResImage } from "@/lib/images";
import { resolveUser, commentCountOf } from "@/lib/social";
import { useCurrentUser, displayUser } from "@/lib/identity";
import type { Pin } from "@/lib/pins";
import { Avatar, Icons } from "@/components/ui";
import { useStore } from "@/components/app/store";
import { useMaxi } from "@/components/app/maxi-provider";

export function PostModal() {
  const { openPostId, openPost, posts, toggleLike, toggleSave, addComment, replyAsMaxi } = useStore();
  const [draft, setDraft] = useState("");
  const [mediaIndex, setMediaIndex] = useState(0);
  const mediaRef = useRef<HTMLDivElement>(null);
  const me = useCurrentUser();
  const { commentReply, addPinToCart } = useMaxi();
  const post = posts.find((p) => p.id === openPostId);
  if (!post) return null;
  const gallery = [...new Set([post.product.image, ...(post.product.images ?? [])].filter(Boolean) as string[])];
  const visibleMediaIndex = Math.min(mediaIndex, Math.max(0, gallery.length - 1));
  const u = post.user === "you" ? me : resolveUser(post);
  const commentTotal = commentCountOf(post);
  const asPin: Pin = {
    id: post.product.id,
    title: post.product.name,
    image: post.product.image ?? "",
    thumb: post.product.image ?? "",
    source: post.product.brand,
    brand: post.product.brand,
    url: post.url ?? "",
    price: post.product.price,
    grad: post.product.grad,
    emoji: post.product.emoji,
    category: "gifts",
  };

  return (
    <div
      className="fixed inset-0 z-[80] flex items-center justify-center bg-black/75 p-0 backdrop-blur-sm sm:p-6"
      onClick={() => openPost(null)}
    >
      <button
        onClick={() => openPost(null)}
        className="absolute right-4 top-4 z-10 text-white/80 hover:text-white"
        aria-label="Close"
      >
        <Icons.close size={30} />
      </button>

      <div
        className="flex h-full w-full max-w-4xl flex-col overflow-hidden bg-surface sm:h-[85vh] sm:rounded-2xl md:flex-row"
        onClick={(e) => e.stopPropagation()}
      >
        {/* media */}
        <div
          className="relative grid flex-1 place-items-center md:min-h-0"
          style={{ background: GRADIENTS[post.product.grad] }}
        >
          {gallery.length ? (
            <div
              ref={mediaRef}
              className="absolute inset-0 flex snap-x snap-mandatory overflow-x-auto [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
              onScroll={(event) => {
                const width = event.currentTarget.clientWidth;
                if (width) setMediaIndex(Math.round(event.currentTarget.scrollLeft / width));
              }}
            >
              {gallery.map((image, index) => (
                <div key={image} className="relative min-w-full snap-center">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img
                    src={hiResImage(image)}
                    alt={`${post.product.name} — image ${index + 1}`}
                    className="h-full w-full object-cover"
                    onError={(event) => { event.currentTarget.style.display = "none"; }}
                  />
                </div>
              ))}
            </div>
          ) : (
            <span className="text-[120px]">{post.product.emoji}</span>
          )}
          {gallery.length > 1 && (
            <>
              <span className="absolute right-4 top-4 rounded-full bg-black/60 px-2.5 py-1 text-xs font-semibold text-white">
                {visibleMediaIndex + 1}/{gallery.length}
              </span>
              {visibleMediaIndex > 0 && (
                <button
                  aria-label="Previous image"
                  className="absolute left-3 grid h-9 w-9 place-items-center rounded-full bg-black/45 text-2xl text-white"
                  onClick={() => mediaRef.current?.scrollTo({ left: (visibleMediaIndex - 1) * mediaRef.current.clientWidth, behavior: "smooth" })}
                >
                  ‹
                </button>
              )}
              {visibleMediaIndex < gallery.length - 1 && (
                <button
                  aria-label="Next image"
                  className="absolute right-3 grid h-9 w-9 place-items-center rounded-full bg-black/45 text-2xl text-white"
                  onClick={() => mediaRef.current?.scrollTo({ left: (visibleMediaIndex + 1) * mediaRef.current.clientWidth, behavior: "smooth" })}
                >
                  ›
                </button>
              )}
            </>
          )}
          <div className="absolute bottom-4 left-4 rounded-xl bg-black/55 px-4 py-2.5 text-white backdrop-blur">
            <p className="text-sm font-bold">{post.product.name}</p>
            <p className="text-xs text-white/80">
              {post.product.brand}
              {post.product.price > 0 ? ` · $${post.product.price}` : ""}
              {post.product.price > 0 && post.product.was && (
                <span className="ml-1.5 line-through opacity-70">${post.product.was}</span>
              )}
            </p>
          </div>
        </div>

        {/* comments pane */}
        <div className="flex w-full flex-col border-t border-line md:w-[360px] md:border-l md:border-t-0">
          <div className="flex items-center gap-3 border-b border-line px-4 py-3">
            <Avatar grad={u.grad} label={u.name} size={34} />
            <span className="text-sm font-bold text-ink">{u.handle}</span>
            <button className="ml-auto text-ink-soft">
              <Icons.more size={20} />
            </button>
          </div>

          {/* scrollable comments */}
          <div className="flex-1 space-y-4 overflow-y-auto px-4 py-4">
            {post.caption && (
              <div className="flex gap-3">
                <Avatar grad={u.grad} label={u.name} size={32} />
                <p className="text-sm text-ink">
                  <span className="font-bold">{u.handle}</span> {post.caption}
                </p>
              </div>
            )}
            {post.comments.map((c) => {
              const cu = displayUser(c.user, me);
              return (
                <div key={c.id} className="flex gap-3">
                  <Avatar grad={cu.grad} label={cu.name} size={32} />
                  <p className="text-sm text-ink">
                    <span className="font-bold">{cu.handle}</span> {c.text}
                  </p>
                </div>
              );
            })}
            {post.comments.length === 0 &&
              (commentTotal > 0 && post.url ? (
                <a
                  href={post.url}
                  target="_blank"
                  rel="noreferrer"
                  className="block pt-6 text-center text-sm font-semibold text-coral"
                >
                  View all {commentTotal.toLocaleString()} comments on Reddit
                </a>
              ) : (
                <p className="pt-6 text-center text-sm text-ink-faint">
                  No comments yet. Start the conversation.
                </p>
              ))}
          </div>

          {/* actions */}
          <div className="border-t border-line px-4 py-3">
            <div className="flex items-center gap-4 text-ink">
              <button onClick={() => toggleLike(post.id)} className={post.liked ? "text-coral" : ""}>
                {post.liked ? <Icons.heartFill size={26} /> : <Icons.heart size={26} />}
              </button>
              <Icons.comment size={25} />
              <button
                onClick={() => {
                  const url = `${window.location.origin}/feed`;
                  const priceTag = post.product.price > 0 ? ` ($${post.product.price})` : "";
                  const text = `Check out this find: ${post.product.name}${priceTag} on Giftmaxxing`;
                  if (typeof navigator !== "undefined" && navigator.share) {
                    navigator.share({ title: "Giftmaxxing", text, url }).catch(() => {});
                  } else if (typeof navigator !== "undefined" && navigator.clipboard) {
                    navigator.clipboard.writeText(`${text} — ${url}`).catch(() => {});
                  }
                }}
                aria-label="Share"
              >
                <Icons.share size={24} />
              </button>
              <button
                onClick={() => toggleSave(post.id)}
                className="ml-auto"
              >
                {post.saved ? <Icons.bookmarkFill size={25} /> : <Icons.bookmark size={25} />}
              </button>
            </div>
            <p className="mt-2 text-sm font-bold text-ink">
              {post.likes.toLocaleString()} likes
            </p>
            <p className="text-xs text-ink-faint">{post.time} ago</p>
            <button
              onClick={() => addPinToCart(asPin)}
              className="mt-3 w-full rounded-full bg-coral py-2.5 text-sm font-bold text-white transition-opacity hover:opacity-90"
            >
              Add to cart{post.product.price > 0 ? ` · $${post.product.price}` : ""}
            </button>
            <a
              href={productAmazonUrl({ name: post.product.name, brand: post.product.brand })}
              target="_blank"
              rel={AFFILIATE_REL}
              className="mt-2 flex w-full items-center justify-center gap-1.5 rounded-full border border-line py-2.5 text-sm font-bold text-ink transition-colors hover:bg-ink/5"
            >
              View on Amazon
              <Icons.arrow size={14} className="-rotate-45" />
            </a>
          </div>

          {/* add comment */}
          <form
            onSubmit={(e) => {
              e.preventDefault();
              const text = draft.trim();
              if (!text) return;
              addComment(post.id, text);
              if (/@maxi\b/i.test(text)) {
                const query = text.replace(/@maxi\b/i, "").trim() || `gift ideas like ${post.product.name}`;
                // Maxi replies inline in the thread (does NOT open the side panel).
                void commentReply(query, post.product.name).then((reply) => replyAsMaxi(post.id, reply));
              }
              setDraft("");
            }}
            className="flex items-center gap-2 border-t border-line px-4 py-3"
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
      </div>
    </div>
  );
}
