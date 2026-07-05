"use client";

// ChatFlow — a scripted conversation that FEELS like texting a person.
//
// Both the gift consult (/gift) and onboarding (/onboarding) are "agent"
// conversations with a fixed script: the agent asks, the user taps a chip or
// types, the agent follows up. This component renders that script with the
// pacing that sells it (typing dots, staggered bubbles, an undo), while every
// answer stays deterministic + parseable — no LLM required for the flow itself.
//
// The script is data (ChatStep[]), so the iOS app can replay the exact same
// conversations from a shared spec. See docs/intentional-gifting.md.

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Maxi } from "@/components/ui";

export type ChatAnswers = Record<string, unknown>;

export type ChatOption = { value: string; label: string; emoji?: string };

export type ChatStep = {
  id: string;
  // Agent bubbles for this step (computed from answers so far → lets prompts
  // use the recipient's name, chosen budget, etc.)
  prompts: (a: ChatAnswers) => string[];
  input: "chips" | "multichips" | "text";
  options?: ChatOption[];
  placeholder?: string;
  // For "chips": also accept free text (e.g. budget chips + "around $80").
  allowText?: boolean;
  // Parse free text into an answer; return null to reject (agent nudges).
  parseText?: (t: string, a: ChatAnswers) => { value: unknown; label: string } | null;
  // Agent's nudge when parseText rejects.
  rejectText?: string;
  minPicks?: number; // multichips: minimum selections
  confirmLabel?: string; // multichips: submit button label
  skippable?: boolean; // renders a "Skip" ghost option (answer = null)
  skipLabel?: string;
  // Reducer applied AFTER this step's value lands — lets a step assemble
  // composite answers (e.g. the events loop collecting {name, date} entries).
  onAnswer?: (a: ChatAnswers, value: unknown) => ChatAnswers;
  // Branching: return the id of the next step, null to finish the conversation,
  // or undefined for "just continue in order". Enables skips + loops.
  next?: (a: ChatAnswers, value: unknown) => string | null | undefined;
};

type Msg =
  | { id: string; from: "agent"; text: string }
  | { id: string; from: "you"; text: string };

let MID = 0;
const mkId = () => `cf${Date.now().toString(36)}_${MID++}`;

const TYPE_MS = 420; // typing-dots dwell per agent bubble

export function ChatFlow({
  steps,
  onComplete,
  intro,
}: {
  steps: ChatStep[];
  onComplete: (answers: ChatAnswers) => void;
  intro?: string[]; // one-time agent bubbles before step 0
}) {
  const [messages, setMessages] = useState<Msg[]>([]);
  const [stepIdx, setStepIdx] = useState(-1); // -1 while intro plays
  const [typing, setTyping] = useState(false);
  const [inputEnabled, setInputEnabled] = useState(false);
  const [picks, setPicks] = useState<Set<string>>(new Set());
  const [text, setText] = useState("");
  const answersRef = useRef<ChatAnswers>({});
  // Snapshot per answered step so "change answer" can rewind cleanly.
  const historyRef = useRef<{ msgCount: number; answers: ChatAnswers; stepIdx: number }[]>([]);
  const timersRef = useRef<number[]>([]);
  const endRef = useRef<HTMLDivElement | null>(null);
  const inputRef = useRef<HTMLInputElement | null>(null);
  const step = stepIdx >= 0 && stepIdx < steps.length ? steps[stepIdx] : null;

  const clearTimers = () => {
    timersRef.current.forEach((t) => window.clearTimeout(t));
    timersRef.current = [];
  };

  // Queue agent bubbles with typing-dot pacing, then unlock the input.
  const speak = useCallback((lines: string[], after?: () => void) => {
    setInputEnabled(false);
    let delay = 120;
    for (const line of lines) {
      timersRef.current.push(window.setTimeout(() => setTyping(true), delay));
      delay += TYPE_MS + Math.min(600, line.length * 6);
      timersRef.current.push(
        window.setTimeout(() => {
          setTyping(false);
          setMessages((m) => [...m, { id: mkId(), from: "agent", text: line }]);
        }, delay),
      );
      delay += 140;
    }
    timersRef.current.push(
      window.setTimeout(() => {
        setInputEnabled(true);
        after?.();
      }, delay),
    );
  }, []);

  const askStep = useCallback(
    (idx: number) => {
      setStepIdx(idx);
      setPicks(new Set());
      setText("");
      speak(steps[idx].prompts(answersRef.current));
    },
    [speak, steps],
  );

  // Mount: play the intro, then ask the first question. Kickoff rides a 0ms
  // timer so no setState happens synchronously in the effect body (and the
  // strict-mode double-mount is defused by the cleanup clearing timers +
  // the reset happening inside the surviving timer).
  useEffect(() => {
    timersRef.current.push(
      window.setTimeout(() => {
        setMessages([]);
        if (intro?.length) speak(intro, () => askStep(0));
        else askStep(0);
      }, 0),
    );
    return clearTimers;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Keep the newest bubble in view.
  useEffect(() => {
    endRef.current?.scrollIntoView({ behavior: "smooth", block: "end" });
  }, [messages, typing]);

  const advance = useCallback(
    (value: unknown, label: string) => {
      if (!step) return;
      historyRef.current.push({
        msgCount: messages.length,
        answers: { ...answersRef.current },
        stepIdx,
      });
      let nextAnswers: ChatAnswers = { ...answersRef.current, [step.id]: value };
      if (step.onAnswer) nextAnswers = step.onAnswer(nextAnswers, value);
      answersRef.current = nextAnswers;
      setMessages((m) => [...m, { id: mkId(), from: "you", text: label }]);

      // Resolve the next step: explicit branch → id lookup; default → in order.
      const branch = step.next?.(nextAnswers, value);
      let next: number;
      if (branch === null) next = steps.length;
      else if (typeof branch === "string") {
        const found = steps.findIndex((s) => s.id === branch);
        next = found >= 0 ? found : stepIdx + 1;
      } else next = stepIdx + 1;

      if (next < steps.length) askStep(next);
      else {
        setInputEnabled(false);
        setStepIdx(steps.length); // conversation over
        onComplete(answersRef.current);
      }
    },
    [step, stepIdx, steps, messages.length, askStep, onComplete],
  );

  const undo = useCallback(() => {
    const prev = historyRef.current.pop();
    if (!prev) return;
    clearTimers();
    setTyping(false);
    answersRef.current = prev.answers;
    setMessages((m) => m.slice(0, prev.msgCount));
    askStep(prev.stepIdx);
  }, [askStep]);

  const submitText = useCallback(() => {
    if (!step) return;
    const clean = text.trim();
    if (!clean) return;
    const parsed = step.parseText
      ? step.parseText(clean, answersRef.current)
      : { value: clean, label: clean };
    if (!parsed) {
      setMessages((m) => [...m, { id: mkId(), from: "you", text: clean }]);
      setText("");
      speak([step.rejectText ?? "Hmm, give me that one more time?"]);
      return;
    }
    setText("");
    advance(parsed.value, parsed.label);
  }, [step, text, advance, speak]);

  const togglePick = useCallback((v: string) => {
    setPicks((prev) => {
      const next = new Set(prev);
      if (next.has(v)) next.delete(v);
      else next.add(v);
      return next;
    });
  }, []);

  const confirmPicks = useCallback(() => {
    if (!step) return;
    const values = (step.options ?? []).filter((o) => picks.has(o.value));
    advance(
      values.map((v) => v.value),
      values.length
        ? values.map((v) => `${v.emoji ?? ""} ${v.label}`.trim()).join(", ")
        : "None of these, really",
    );
  }, [step, picks, advance]);

  const showText = step && (step.input === "text" || (step.allowText && step.input === "chips"));
  // Derived from state (not the history ref) so it re-renders correctly.
  const canUndo = !!step && messages.some((m) => m.from === "you");

  const chipBase =
    "flex items-center gap-1.5 rounded-full border-2 px-4 py-2 text-sm font-semibold transition-all active:scale-95";

  const options = useMemo(() => step?.options ?? [], [step]);

  return (
    <div className="flex h-full min-h-0 flex-col">
      {/* Transcript */}
      <div className="flex-1 space-y-3 overflow-y-auto px-1 pb-4 pt-2">
        {messages.map((m) =>
          m.from === "agent" ? (
            <div key={m.id} className="flex items-end gap-2.5 animate-rise">
              <div className="shrink-0"><Maxi size={30} /></div>
              <p className="max-w-[82%] rounded-2xl rounded-bl-md border border-line bg-surface px-4 py-2.5 text-[15px] leading-snug text-ink shadow-sm">
                {m.text}
              </p>
            </div>
          ) : (
            <div key={m.id} className="flex justify-end animate-rise">
              <p className="max-w-[82%] rounded-2xl rounded-br-md bg-ink px-4 py-2.5 text-[15px] leading-snug text-cream">
                {m.text}
              </p>
            </div>
          ),
        )}
        {typing && (
          <div className="flex items-end gap-2.5">
            <div className="shrink-0"><Maxi size={30} /></div>
            <div className="flex gap-1 rounded-2xl rounded-bl-md border border-line bg-surface px-4 py-3.5 shadow-sm">
              <Dot delay="0ms" /><Dot delay="140ms" /><Dot delay="280ms" />
            </div>
          </div>
        )}
        <div ref={endRef} />
      </div>

      {/* Answer area */}
      {step && (
        <div className="shrink-0 border-t border-line/70 pt-3">
          {canUndo && (
            <button
              onClick={undo}
              className="mb-2 text-xs font-semibold text-ink-faint transition-colors hover:text-coral"
            >
              ↩ change my last answer
            </button>
          )}

          {(step.input === "chips" || step.input === "multichips") && inputEnabled && (
            <div className="mb-2 flex flex-wrap gap-2">
              {options.map((o) => {
                const active = step.input === "multichips" && picks.has(o.value);
                return (
                  <button
                    key={o.value}
                    onClick={() =>
                      step.input === "chips"
                        ? advance(o.value, `${o.emoji ?? ""} ${o.label}`.trim())
                        : togglePick(o.value)
                    }
                    className={`${chipBase} ${
                      active
                        ? "border-coral bg-coral-soft/60 text-ink shadow-sm"
                        : "border-line bg-surface text-ink-soft hover:border-ink/25 hover:text-ink"
                    }`}
                  >
                    {o.emoji && <span>{o.emoji}</span>}
                    {o.label}
                  </button>
                );
              })}
              {step.skippable && step.input === "chips" && (
                <button
                  onClick={() => advance(null, step.skipLabel ?? "Skip")}
                  className={`${chipBase} border-transparent bg-transparent text-ink-faint hover:text-ink`}
                >
                  {step.skipLabel ?? "Skip"}
                </button>
              )}
            </div>
          )}

          {step.input === "multichips" && inputEnabled && (
            <button
              onClick={confirmPicks}
              disabled={picks.size < (step.minPicks ?? 1)}
              className="mb-2 w-full rounded-full bg-ink py-3 text-sm font-bold text-cream transition-opacity hover:opacity-90 disabled:opacity-35"
            >
              {step.confirmLabel ?? "That's them"}
              {(step.minPicks ?? 1) > 1 && picks.size < (step.minPicks ?? 1)
                ? ` (pick ${(step.minPicks ?? 1) - picks.size} more)`
                : ""}
            </button>
          )}

          {showText && (
            <div className="flex gap-2">
              <input
                ref={inputRef}
                type="text"
                value={text}
                disabled={!inputEnabled}
                onChange={(e) => setText(e.target.value)}
                placeholder={step.placeholder ?? "Type a reply…"}
                enterKeyHint="send"
                className="min-w-0 flex-1 rounded-full border border-line bg-surface px-4 py-3 text-[15px] text-ink outline-none transition-shadow focus:border-coral focus:ring-2 focus:ring-coral/20 disabled:opacity-50"
                onKeyDown={(e) => {
                  if (e.key === "Enter") submitText();
                }}
              />
              <button
                onClick={submitText}
                disabled={!inputEnabled || !text.trim()}
                aria-label="Send"
                className="grid h-12 w-12 shrink-0 place-items-center rounded-full bg-coral text-white transition-opacity hover:opacity-90 disabled:opacity-35"
              >
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M5 12h13M13 6l6 6-6 6" />
                </svg>
              </button>
            </div>
          )}

          {step.input === "text" && step.skippable && inputEnabled && (
            <button
              onClick={() => advance(null, step.skipLabel ?? "Skip")}
              className="mt-2 text-xs font-semibold text-ink-faint transition-colors hover:text-ink"
            >
              {step.skipLabel ?? "Skip this one"}
            </button>
          )}
        </div>
      )}
    </div>
  );
}

function Dot({ delay }: { delay: string }) {
  return (
    <span
      className="h-1.5 w-1.5 animate-bounce rounded-full bg-ink-faint"
      style={{ animationDelay: delay }}
    />
  );
}
