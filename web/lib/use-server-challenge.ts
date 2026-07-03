"use client";

import { useCallback, useRef } from "react";
import { createChallenge } from "@/lib/api";
import { buildInviteUrl } from "@/lib/invite";
import { seedKeysFromSwipes } from "@/lib/swipes";

// Sender-side server challenge, shared by /challenge and /feed/swipe: when the
// share sheet opens, POST /challenges seeded with the sender's recent "yes"
// swipes and return an invite URL carrying the challengeId. Cached per
// personalization fields + seeds so repeat opens don't re-create; returns null
// (→ legacy local-deck link) when there's no seed or the API is down, so
// sharing never blocks.
export function useServerChallengePrepare(opts: {
  senderId: string | null;
  inviterName: string;
  to?: string;
  occasion?: string;
  date?: string;
}) {
  const cacheRef = useRef<{ key: string; url: string } | null>(null);
  const { senderId, inviterName, to, occasion, date } = opts;

  return useCallback(async (): Promise<string | null> => {
    if (!senderId) return null;
    const seeds = seedKeysFromSwipes(8);
    if (!seeds.length) return null;

    const key = JSON.stringify([senderId, inviterName, to, occasion, date, seeds]);
    if (cacheRef.current?.key === key) return cacheRef.current.url;

    const challengeId = await createChallenge({
      senderId,
      seedKeys: seeds,
      inviterName,
      to,
      occasion,
      date,
    });
    if (!challengeId) return null;

    const url = buildInviteUrl(inviterName, { senderId, to, occasion, date, challengeId });
    cacheRef.current = { key, url };
    return url;
  }, [senderId, inviterName, to, occasion, date]);
}
