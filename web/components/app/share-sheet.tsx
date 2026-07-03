"use client";

import { useCallback, useEffect, useState, useSyncExternalStore } from "react";
import { Icons } from "@/components/ui";
import {
  loadShares,
  recordShare,
  relativeShareTime,
  SHARES_EVENT,
  type ShareRecord,
} from "@/lib/share-tracking";

// Wispr-style share sheet: one tap opens a bottom sheet (mobile) / dialog
// (desktop) with copy-link + every easy channel. Instagram has no web
// link-share intent, so we copy the link and open IG for pasting into a DM/story.

const enc = encodeURIComponent;

// Robust copy: the async Clipboard API is blocked in some contexts (e.g. an
// embedded preview iframe without clipboard-write permission), so fall back to a
// hidden <textarea> + execCommand. Returns whether the copy succeeded.
async function copyToClipboard(text: string): Promise<boolean> {
  try {
    if (typeof navigator !== "undefined" && navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text);
      return true;
    }
  } catch {
    /* fall through to the legacy path */
  }
  try {
    const ta = document.createElement("textarea");
    ta.value = text;
    ta.setAttribute("readonly", "");
    ta.style.position = "fixed";
    ta.style.top = "0";
    ta.style.opacity = "0";
    document.body.appendChild(ta);
    ta.select();
    const ok = document.execCommand("copy");
    document.body.removeChild(ta);
    return ok;
  } catch {
    return false;
  }
}

export function ShareSheet({
  url,
  text,
  title = "Giftmaxxing",
  subject = "Find me the perfect gift",
  triggerLabel = "Share the challenge",
  triggerClassName,
  note,
  recipientName = "",
  prepare,
}: {
  url: string;
  text: string;
  title?: string;
  subject?: string;
  triggerLabel?: string;
  triggerClassName?: string;
  note?: React.ReactNode;
  recipientName?: string;
  /** Optional async link upgrade, awaited when the trigger is tapped — the
   *  challenge pages use it to POST /challenges and return a link carrying
   *  the challengeId (server-built deck). null → share the plain url. */
  prepare?: () => Promise<string | null>;
}) {
  const [open, setOpen] = useState(false);
  const [copied, setCopied] = useState(false);
  const [shares, setShares] = useState<ShareRecord[]>([]);
  const [showHistory, setShowHistory] = useState(false);
  const [preparing, setPreparing] = useState(false);
  const [preparedUrl, setPreparedUrl] = useState<string | null>(null);

  // The link actually shared — the prepared (server-deck) one when available.
  const shareUrl = preparedUrl ?? url;

  const openSheet = useCallback(async () => {
    if (prepare && !preparing) {
      setPreparing(true);
      try {
        const upgraded = await prepare();
        setPreparedUrl(upgraded);
      } catch {
        setPreparedUrl(null);
      }
      setPreparing(false);
    }
    setOpen(true);
  }, [prepare, preparing]);

  // Load share history on mount and listen for updates.
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setShares(loadShares());
    const sync = () => setShares(loadShares());
    window.addEventListener(SHARES_EVENT, sync);
    return () => window.removeEventListener(SHARES_EVENT, sync);
  }, []);

  const track = useCallback(
    (channel: string) => recordShare(channel, recipientName, shareUrl),
    [recipientName, shareUrl]
  );
  // Detect the Web Share API without a setState-in-effect (avoids hydration
  // drift): server snapshot is false, client snapshot reflects real capability.
  const canNativeShare = useSyncExternalStore(
    () => () => {},
    () => typeof navigator !== "undefined" && typeof navigator.share === "function",
    () => false
  );

  // Lock body scroll while the sheet is open.
  useEffect(() => {
    if (!open) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = prev;
    };
  }, [open]);

  const copy = async () => {
    await copyToClipboard(shareUrl);
    setCopied(true);
    track("copy");
    window.setTimeout(() => setCopied(false), 2400);
  };

  const nativeShare = async () => {
    try {
      await navigator.share({ title, text, url: shareUrl });
      track("native");
      setOpen(false);
    } catch {
      /* dismissed */
    }
  };

  const instagram = async () => {
    await copyToClipboard(shareUrl);
    setCopied(true);
    window.setTimeout(() => setCopied(false), 2400);
    track("instagram");
    window.open("https://www.instagram.com/", "_blank", "noopener,noreferrer");
  };

  const msg = `${text} ${shareUrl}`;
  const links: { key: string; label: string; emoji: string; href: string; external?: boolean }[] = [
    { key: "email", label: "Email", emoji: "✉️", href: `mailto:?subject=${enc(subject)}&body=${enc(msg)}` },
    { key: "sms", label: "Messages", emoji: "💬", href: `sms:?&body=${enc(msg)}` },
    { key: "whatsapp", label: "WhatsApp", emoji: "🟢", href: `https://wa.me/?text=${enc(msg)}`, external: true },
    { key: "x", label: "X", emoji: "𝕏", href: `https://twitter.com/intent/tweet?text=${enc(text)}&url=${enc(shareUrl)}`, external: true },
    { key: "telegram", label: "Telegram", emoji: "📨", href: `https://t.me/share/url?url=${enc(shareUrl)}&text=${enc(text)}`, external: true },
    { key: "messenger", label: "Messenger", emoji: "💙", href: `fb-messenger://share?link=${enc(shareUrl)}`, external: true },
  ];

  const trackLink = (key: string) => track(key);
  const recentShares = shares.slice(0, 5);

  return (
    <>
      <button
        onClick={() => void openSheet()}
        disabled={preparing}
        className={`${
          triggerClassName ??
          "inline-flex items-center gap-2 rounded-full bg-coral px-5 py-2.5 text-sm font-bold text-white shadow-lg shadow-coral/25 transition-opacity hover:opacity-90"
        } ${preparing ? "cursor-wait opacity-70" : ""}`}
      >
        <Icons.share size={16} /> {preparing ? "Building their deck…" : triggerLabel}
      </button>

      {open && (
        <div
          className="fixed inset-0 z-50 flex items-end justify-center bg-ink/40 backdrop-blur-sm sm:items-center"
          onClick={() => setOpen(false)}
        >
          <div
            onClick={(e) => e.stopPropagation()}
            className="w-full max-w-md rounded-t-3xl border border-line bg-surface p-5 shadow-2xl sm:rounded-3xl"
          >
            <div className="mb-4 flex items-center justify-between">
              <h3 className="font-display text-lg font-extrabold text-ink">
                Share your gift challenge
              </h3>
              <button
                onClick={() => setOpen(false)}
                aria-label="Close"
                className="text-ink-faint transition-colors hover:text-ink"
              >
                <Icons.close size={20} />
              </button>
            </div>

            {/* Link preview + copy */}
            <div className="mb-4 flex items-center gap-2 rounded-xl border border-line bg-cream px-3 py-2.5">
              <span className="truncate text-sm text-ink-soft">{shareUrl}</span>
              <button
                onClick={copy}
                className="ml-auto shrink-0 rounded-full bg-ink px-3 py-1.5 text-xs font-bold text-cream transition-opacity hover:opacity-90"
              >
                {copied ? "Copied!" : "Copy"}
              </button>
            </div>

            {copied && (
              <p className="mb-3 -mt-1.5 rounded-lg bg-green-50 px-3 py-2 text-center text-xs font-semibold text-green-700">
                ✓ Link copied — send it to anyone. Their responses show up in your activity once you sign in.
              </p>
            )}

            {/* Channels */}
            <div className="grid grid-cols-4 gap-2">
              <Tile emoji="🔗" label={copied ? "Copied" : "Copy link"} onClick={copy} />
              {links.map((l) => (
                <a
                  key={l.key}
                  href={l.href}
                  target={l.external ? "_blank" : undefined}
                  rel={l.external ? "noopener noreferrer" : undefined}
                  onClick={() => trackLink(l.key)}
                  className="flex flex-col items-center gap-1.5 rounded-2xl border border-line bg-cream py-3 transition-colors hover:bg-coral-soft"
                >
                  <span className="grid h-10 w-10 place-items-center rounded-full bg-surface text-xl">
                    {l.emoji}
                  </span>
                  <span className="text-[11px] font-semibold text-ink">{l.label}</span>
                </a>
              ))}
              <Tile emoji="📸" label="Instagram" onClick={instagram} />
              {canNativeShare && <Tile emoji="⤴️" label="More" onClick={nativeShare} />}
            </div>

            {note && (
              <div className="mt-4 text-[11px] leading-relaxed text-ink-faint">{note}</div>
            )}

            {/* Share history */}
            {recentShares.length > 0 && (
              <div className="mt-4 border-t border-line pt-3">
                <button
                  onClick={() => setShowHistory((v) => !v)}
                  className="flex w-full items-center justify-between text-xs font-bold text-ink-soft"
                >
                  <span>Shared {shares.length} time{shares.length !== 1 ? "s" : ""}</span>
                  <span className="text-ink-faint">{showHistory ? "Hide" : "Show"}</span>
                </button>
                {showHistory && (
                  <ul className="mt-2 space-y-1.5">
                    {recentShares.map((s) => (
                      <li key={s.id} className="flex items-center gap-2 text-[11px] text-ink-soft">
                        <span className="capitalize">{s.channel}</span>
                        <span className="text-ink-faint">·</span>
                        <span className="font-medium">{s.recipientName}</span>
                        <span className="ml-auto text-ink-faint">{relativeShareTime(s.sharedAt)}</span>
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            )}
          </div>
        </div>
      )}
    </>
  );
}

function Tile({
  emoji,
  label,
  onClick,
}: {
  emoji: string;
  label: string;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className="flex flex-col items-center gap-1.5 rounded-2xl border border-line bg-cream py-3 transition-colors hover:bg-coral-soft"
    >
      <span className="grid h-10 w-10 place-items-center rounded-full bg-surface text-xl">
        {emoji}
      </span>
      <span className="text-[11px] font-semibold text-ink">{label}</span>
    </button>
  );
}
