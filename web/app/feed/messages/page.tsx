"use client";

import { Suspense, useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { USERS, GROUP_CHATS, type ChatMessage, type GroupChat } from "@/lib/social";
import { GRADIENTS } from "@/lib/data";
import { Avatar, Icons } from "@/components/ui";
import { useMyPools } from "@/lib/use-pools";
import { useCurrentUser } from "@/lib/identity";
import { getMyUserId } from "@/lib/api";
import {
  FRIENDS_EVENT,
  fetchDmMessages,
  listDms,
  sendDmMessage,
  type DmMessage,
  type DmThread,
} from "@/lib/friends";

const STORAGE_KEY = "giftmaxxing_messages";

function loadConversations(): GroupChat[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) return JSON.parse(raw) as GroupChat[];
  } catch {
    /* ignore */
  }
  return GROUP_CHATS.filter((c) => !c.newChat);
}

function saveConversations(chats: GroupChat[]): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(chats));
  } catch {
    /* quota */
  }
}

function lastMessage(chat: GroupChat): ChatMessage | undefined {
  return chat.messages[chat.messages.length - 1];
}

function chatTitle(chat: GroupChat): string {
  const u = USERS[chat.forUser];
  const name = u?.name ?? chat.forUser;
  if (chat.occasion === "birthday") return `${name}'s Birthday`;
  if (chat.occasion === "farewell") return `${name}'s Farewell`;
  if (chat.occasion === "housewarming") return `${name}'s Housewarming`;
  if (chat.occasion === "anniversary") return `${name}'s Anniversary`;
  if (chat.occasion) return `${name} — ${chat.occasion}`;
  return name;
}

function memberNames(chat: GroupChat): string {
  return chat.members
    .filter((m) => m !== "you")
    .map((m) => USERS[m]?.name?.split(" ")[0] ?? m)
    .join(", ");
}

function formatDmTime(at?: number): string {
  if (!at) return "";
  const d = new Date(at);
  const now = new Date();
  if (d.toDateString() === now.toDateString()) {
    return d.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
  }
  return d.toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

export default function MessagesPage() {
  return (
    <Suspense fallback={null}>
      <MessagesInner />
    </Suspense>
  );
}

function MessagesInner() {
  const { pools } = useMyPools();
  const me = useCurrentUser();
  const searchParams = useSearchParams();
  const myId = getMyUserId() ?? "you";

  const [chats, setChats] = useState<GroupChat[]>([]);
  const [dms, setDms] = useState<DmThread[]>([]);
  const [activeId, setActiveId] = useState<string | null>(null);
  const [activeDmId, setActiveDmId] = useState<string | null>(null);
  const [dmMessages, setDmMessages] = useState<DmMessage[]>([]);
  const [draft, setDraft] = useState("");
  const scrollRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const refreshDms = useCallback(async () => {
    const items = await listDms(myId);
    setDms(items);
  }, [myId]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- localStorage unavailable during SSR
    setChats(loadConversations());
    void refreshDms();
    const on = () => void refreshDms();
    window.addEventListener(FRIENDS_EVENT, on);
    return () => window.removeEventListener(FRIENDS_EVENT, on);
  }, [refreshDms]);

  // Deep-link: /feed/messages?dm=<threadId>
  useEffect(() => {
    const dm = searchParams.get("dm");
    if (dm) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setActiveDmId(dm);
      setActiveId(null);
    }
  }, [searchParams]);

  useEffect(() => {
    if (!activeDmId) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setDmMessages([]);
      return;
    }
    let cancelled = false;
    (async () => {
      const items = await fetchDmMessages(activeDmId);
      if (!cancelled) setDmMessages(items);
    })();
    return () => {
      cancelled = true;
    };
  }, [activeDmId]);

  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [activeId, activeDmId, chats, dmMessages]);

  const activeChat = chats.find((c) => c.id === activeId) ?? null;
  const activeDm = dms.find((d) => d.threadId === activeDmId) ?? null;

  const sendMessage = useCallback(() => {
    const text = draft.trim();
    if (!text) return;

    if (activeDmId) {
      void (async () => {
        const msg = await sendDmMessage({
          threadId: activeDmId,
          userId: myId,
          name: me.name,
          text,
        });
        if (msg) {
          setDmMessages((prev) => [...prev, msg]);
          void refreshDms();
        }
      })();
      setDraft("");
      inputRef.current?.focus();
      return;
    }

    if (!activeId) return;
    setChats((prev) => {
      const next = prev.map((c) =>
        c.id === activeId
          ? {
              ...c,
              messages: [
                ...c.messages,
                {
                  id: `msg-${Date.now()}`,
                  user: "you",
                  text,
                  time: "now",
                } satisfies ChatMessage,
              ],
            }
          : c
      );
      saveConversations(next);
      return next;
    });
    setDraft("");
    inputRef.current?.focus();
  }, [draft, activeId, activeDmId, myId, me.name, refreshDms]);

  const total = pools.length + chats.length + dms.length;

  const ConversationList = (
    <div className="flex h-full flex-col">
      <div className="flex items-center justify-between border-b border-line px-4 py-4">
        <h1 className="font-display text-xl font-extrabold text-ink">Messages</h1>
        <Link href="/feed/friends" className="text-xs font-bold text-coral hover:underline">
          Find friends
        </Link>
      </div>

      {total === 0 ? (
        <div className="flex flex-1 flex-col items-center justify-center gap-3 px-6 text-center">
          <span className="text-5xl">✉️</span>
          <p className="text-sm text-ink-faint">
            No conversations yet. Add a friend or start a group gift to message.
          </p>
          <div className="mt-1 flex flex-wrap justify-center gap-2">
            <Link
              href="/feed/friends"
              className="rounded-full bg-coral px-5 py-2.5 text-sm font-bold text-white transition-opacity hover:opacity-90"
            >
              Add friends
            </Link>
            <Link
              href="/feed/pools"
              className="rounded-full bg-ink px-5 py-2.5 text-sm font-bold text-cream transition-opacity hover:opacity-90"
            >
              Start a group gift
            </Link>
          </div>
        </div>
      ) : (
        <div className="flex-1 overflow-y-auto">
          {dms.length > 0 && (
            <div className="divide-y divide-line border-b border-line">
              <p className="px-4 pb-1 pt-3 text-[11px] font-bold uppercase tracking-wide text-ink-faint">
                Friends
              </p>
              {dms.map((dm) => (
                <button
                  key={dm.threadId}
                  onClick={() => {
                    setActiveDmId(dm.threadId);
                    setActiveId(null);
                  }}
                  className="flex w-full items-center gap-3 px-4 py-3.5 text-left transition-colors hover:bg-ink/5"
                >
                  <Avatar
                    grad={USERS[dm.otherUserId]?.grad ?? "coral"}
                    label={dm.otherName ?? dm.otherUserId}
                    size={48}
                  />
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center justify-between gap-2">
                      <p className="truncate text-sm font-bold text-ink">
                        {dm.otherName ?? dm.otherUserId}
                      </p>
                      {dm.lastAt ? (
                        <span className="shrink-0 text-xs text-ink-faint">
                          {formatDmTime(dm.lastAt)}
                        </span>
                      ) : null}
                    </div>
                    <p className="truncate text-xs text-ink-faint">
                      {dm.lastText ?? "Say hi — or gift them something"}
                    </p>
                  </div>
                </button>
              ))}
            </div>
          )}

          {pools.length > 0 && (
            <div className="divide-y divide-line border-b border-line">
              <p className="px-4 pb-1 pt-3 text-[11px] font-bold uppercase tracking-wide text-ink-faint">
                Group gifts
              </p>
              {pools.map((p) => (
                <Link
                  key={p.poolId}
                  href={`/feed/pools/${p.poolId}`}
                  className="flex w-full items-center gap-3 px-4 py-3.5 text-left transition-colors hover:bg-ink/5"
                >
                  <span
                    className="grid h-12 w-12 shrink-0 place-items-center rounded-full text-2xl"
                    style={{ background: GRADIENTS[p.grad] }}
                  >
                    {p.emoji}
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-bold text-ink">{p.title}</p>
                    <p className="truncate text-xs text-ink-soft">
                      Group gift · {p.memberCount} in · ${p.raised} of ${p.goal}
                    </p>
                  </div>
                  <Icons.message size={18} className="shrink-0 text-ink-faint" />
                </Link>
              ))}
            </div>
          )}

          <div className="divide-y divide-line">
            {chats.map((chat) => {
              const last = lastMessage(chat);
              const u = USERS[chat.forUser];
              return (
                <button
                  key={chat.id}
                  onClick={() => {
                    setActiveId(chat.id);
                    setActiveDmId(null);
                  }}
                  className="flex w-full items-center gap-3 px-4 py-3.5 text-left transition-colors hover:bg-ink/5"
                >
                  <div className="relative">
                    <Avatar grad={u?.grad ?? "coral"} label={u?.name ?? "?"} size={48} />
                    {chat.countdown && (
                      <span className="absolute -right-1 -top-1 rounded-full bg-coral px-1.5 py-0.5 text-[10px] font-bold text-white">
                        {chat.countdown}
                      </span>
                    )}
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center justify-between gap-2">
                      <p className="truncate text-sm font-bold text-ink">{chatTitle(chat)}</p>
                      {last && (
                        <span className="shrink-0 text-xs text-ink-faint">{last.time}</span>
                      )}
                    </div>
                    <p className="truncate text-xs text-ink-soft">{memberNames(chat)}</p>
                    {last && (
                      <p className="mt-0.5 truncate text-xs text-ink-faint">
                        {last.user === "you"
                          ? "You: "
                          : `${USERS[last.user]?.name?.split(" ")[0] ?? last.user}: `}
                        {last.text}
                      </p>
                    )}
                  </div>
                </button>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );

  const back = () => {
    setActiveId(null);
    setActiveDmId(null);
  };

  const ConversationDetail = activeChat && (
    <div className="flex h-full flex-col">
      <div className="flex items-center gap-3 border-b border-line px-4 py-3">
        <button onClick={back} className="text-ink" aria-label="Back">
          <Icons.back size={24} />
        </button>
        <Avatar
          grad={USERS[activeChat.forUser]?.grad ?? "coral"}
          label={USERS[activeChat.forUser]?.name ?? "?"}
          size={36}
        />
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-bold text-ink">{chatTitle(activeChat)}</p>
          <p className="truncate text-xs text-ink-faint">
            {memberNames(activeChat)}
            {activeChat.countdown && ` · ${activeChat.countdown} away`}
          </p>
        </div>
        {activeChat.occasion && (
          <span className="shrink-0 rounded-full bg-coral-soft px-2.5 py-1 text-[11px] font-bold text-coral">
            {activeChat.occasion}
          </span>
        )}
      </div>

      <div ref={scrollRef} className="flex-1 space-y-1 overflow-y-auto px-4 py-4">
        {activeChat.messages.length === 0 ? (
          <p className="py-12 text-center text-sm text-ink-faint">
            Start the conversation! Coordinate gifts with your friends.
          </p>
        ) : (
          activeChat.messages.map((msg, i) => {
            const isMe = msg.user === "you";
            const sender = USERS[msg.user];
            const showAvatar =
              !isMe && (i === 0 || activeChat.messages[i - 1].user !== msg.user);
            return (
              <div
                key={msg.id}
                className={`flex items-end gap-2 ${isMe ? "justify-end" : "justify-start"}`}
              >
                {!isMe && (
                  <div className="w-7 shrink-0">
                    {showAvatar && (
                      <Avatar
                        grad={sender?.grad ?? "coral"}
                        label={sender?.name ?? "?"}
                        size={28}
                      />
                    )}
                  </div>
                )}
                <div
                  className={`max-w-[75%] rounded-2xl px-3.5 py-2 ${
                    isMe
                      ? "rounded-br-md bg-coral text-white"
                      : "rounded-bl-md bg-ink/5 text-ink"
                  }`}
                >
                  {showAvatar && !isMe && (
                    <p className="mb-0.5 text-[11px] font-bold text-ink-soft">
                      {sender?.name?.split(" ")[0] ?? msg.user}
                    </p>
                  )}
                  <p className="text-sm leading-relaxed">{msg.text}</p>
                  <p
                    className={`mt-0.5 text-right text-[10px] ${
                      isMe ? "text-white/60" : "text-ink-faint"
                    }`}
                  >
                    {msg.time}
                  </p>
                </div>
              </div>
            );
          })
        )}
      </div>

      <MessageInput
        draft={draft}
        setDraft={setDraft}
        inputRef={inputRef}
        onSend={sendMessage}
      />
    </div>
  );

  const DmDetail = activeDmId && (
    <div className="flex h-full flex-col">
      <div className="flex items-center gap-3 border-b border-line px-4 py-3">
        <button onClick={back} className="text-ink" aria-label="Back">
          <Icons.back size={24} />
        </button>
        <Avatar
          grad={USERS[activeDm?.otherUserId ?? ""]?.grad ?? "coral"}
          label={activeDm?.otherName ?? "Friend"}
          size={36}
        />
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-bold text-ink">
            {activeDm?.otherName ?? "Friend"}
          </p>
          <p className="truncate text-xs text-ink-faint">
            {activeDm?.otherHandle ? `@${activeDm.otherHandle}` : "Direct message"}
          </p>
        </div>
        {activeDm?.otherUserId && (
          <Link
            href={`/feed?giftFor=${encodeURIComponent(activeDm.otherUserId)}`}
            className="shrink-0 rounded-full bg-coral px-3 py-1.5 text-[11px] font-bold text-white"
          >
            Gift them
          </Link>
        )}
      </div>

      <div ref={scrollRef} className="flex-1 space-y-1 overflow-y-auto px-4 py-4">
        {dmMessages.length === 0 ? (
          <p className="py-12 text-center text-sm text-ink-faint">
            You&apos;re friends — say hi, or gift them something from the feed.
          </p>
        ) : (
          dmMessages.map((msg, i) => {
            const isMe = msg.userId === myId || msg.userId === "you";
            const showName =
              !isMe && (i === 0 || dmMessages[i - 1].userId !== msg.userId);
            return (
              <div
                key={msg.id}
                className={`flex items-end gap-2 ${isMe ? "justify-end" : "justify-start"}`}
              >
                <div
                  className={`max-w-[75%] rounded-2xl px-3.5 py-2 ${
                    isMe
                      ? "rounded-br-md bg-coral text-white"
                      : "rounded-bl-md bg-ink/5 text-ink"
                  }`}
                >
                  {showName && (
                    <p className="mb-0.5 text-[11px] font-bold text-ink-soft">{msg.name}</p>
                  )}
                  <p className="text-sm leading-relaxed">{msg.text}</p>
                  <p
                    className={`mt-0.5 text-right text-[10px] ${
                      isMe ? "text-white/60" : "text-ink-faint"
                    }`}
                  >
                    {formatDmTime(msg.at)}
                  </p>
                </div>
              </div>
            );
          })
        )}
      </div>

      <MessageInput
        draft={draft}
        setDraft={setDraft}
        inputRef={inputRef}
        onSend={sendMessage}
      />
    </div>
  );

  return (
    <div className="mx-auto flex h-[calc(100vh-64px)] max-w-3xl flex-col md:h-screen">
      {activeDmId ? DmDetail : activeChat ? ConversationDetail : ConversationList}
    </div>
  );
}

function MessageInput({
  draft,
  setDraft,
  inputRef,
  onSend,
}: {
  draft: string;
  setDraft: (v: string) => void;
  inputRef: React.RefObject<HTMLInputElement | null>;
  onSend: () => void;
}) {
  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        onSend();
      }}
      className="flex items-center gap-2 border-t border-line px-4 py-3"
    >
      <input
        ref={inputRef}
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
        placeholder="Type a message…"
        className="flex-1 rounded-full border border-line bg-surface px-4 py-2.5 text-sm text-ink placeholder:text-ink-faint outline-none focus:border-coral"
      />
      {draft.trim() && (
        <button
          type="submit"
          className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-coral text-white transition-opacity hover:opacity-90"
          aria-label="Send"
        >
          <Icons.share size={18} />
        </button>
      )}
    </form>
  );
}
