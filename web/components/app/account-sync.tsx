"use client";

import { useEffect } from "react";
import { useUser } from "@clerk/nextjs";
import { loadProfile, saveProfile, type UserProfile } from "@/lib/onboarding";
import { fetchMe, saveMe, setMyUserId, identifyMe, claimConnections } from "@/lib/api";
import { getAnonId, clearAnonId } from "@/lib/anon";
import { markProfileSyncSettled } from "@/lib/profile-status";
import { setClerkIdentityCache } from "@/lib/identity";
import { ADMIN_BYPASS, ADMIN_USER_ID } from "@/lib/admin";
import {
  buildCloudPayload,
  restoreInteractionData,
  syncToCloud,
  getStateOwner,
  setStateOwner,
  clearLocalAccountState,
} from "@/lib/sync";

// Bridges Clerk auth → our profile store ("start storing this data").
// When a user is signed in:
//   • if a local profile exists → persist it to the DynamoDB `users` table,
//     keyed by the Clerk userId (so recipients + events are stored server-side);
//   • otherwise → hydrate the local profile from DynamoDB (cross-device restore).
// It also re-pushes whenever onboarding saves a profile (the
// "giftmaxxing:profile" event), so newly-logged dates sync immediately.
//
// Once the restore attempt settles it calls markProfileSyncSettled(), which is
// what lets OnboardingGate stop waiting and either show the feed or redirect —
// so a returning user is never bounced into onboarding mid-restore.
//
// Mounted once in app/layout.tsx inside <ClerkProvider>. Renders nothing.
// Only rendered when Clerk is enabled (layout.tsx guards this).
export function AccountSync() {
  const { isLoaded, isSignedIn, user } = useUser();

  useEffect(() => {
    // Local dev-only admin session: pin the fake admin id, settle the gate, and
    // skip all Clerk-driven sync. Inert (and erased) in production.
    if (ADMIN_BYPASS) {
      setMyUserId(ADMIN_USER_ID);
      markProfileSyncSettled();
      return;
    }

    // Wait for Clerk to resolve the auth state before settling the gate.
    if (!isLoaded) return;

    let cancelled = false;
    // Safety net: never leave the gate spinning if Clerk/the network hangs.
    const safety = setTimeout(markProfileSyncSettled, 6000);
    const settle = () => {
      if (cancelled) return;
      clearTimeout(safety);
      markProfileSyncSettled();
    };

    if (!isSignedIn || !user) {
      // Signed out. If the local state belongs to an ACCOUNT (not guest data),
      // wipe it — the next guest session must not browse someone's profile,
      // likes, or feed personalization. Guest-owned data (no owner mark)
      // stays: that's the try-before-signup flow.
      if (getStateOwner()) {
        clearLocalAccountState();
        window.dispatchEvent(new Event("giftmaxxing:profile"));
      }
      setMyUserId(null);
      setClerkIdentityCache(null, null);
      settle();
      return () => {
        cancelled = true;
        clearTimeout(safety);
      };
    }

    const userId = user.id;
    // Stash the Clerk userId so non-Clerk client code (e.g. the swipe share
    // link) can attribute a shared challenge back to this sender.
    setMyUserId(userId);

    // Claim any challenges shared while signed out (same device): re-key the
    // anon-id soft profiles onto this account, then forget the anon id. On
    // failure we keep the anon id so the next sign-in can retry.
    const anonId = getAnonId();
    if (anonId && anonId !== userId) {
      void claimConnections(anonId, userId).then((claimed) => {
        if (claimed !== null) clearAnonId();
      });
    }

    // Cache Clerk identity (name + avatar) so the identity layer can resolve
    // the display name from Clerk rather than the onboarding profile.
    setClerkIdentityCache(
      user.fullName ?? user.firstName ?? null,
      user.imageUrl ?? null,
    );

    // Ensure a users row (+ graph user node) exists from the very first sign-in,
    // even before onboarding — so every authenticated user is persisted.
    void identifyMe(userId, {
      email: user.primaryEmailAddress?.emailAddress ?? null,
      name: user.fullName ?? null,
      imageUrl: user.imageUrl ?? null,
    });

    // Push the full payload (profile + interactions) to the cloud.
    const push = () => syncToCloud();

    (async () => {
      const owner = getStateOwner();
      if (owner === userId && loadProfile()) {
        // Same account as the local state: local is authoritative (it may be
        // ahead of the cloud) — push the full payload.
        const payload = buildCloudPayload();
        if (payload) await saveMe(userId, payload);
      } else {
        // Different account (or no owned state): the CLOUD is the truth for
        // this identity. Drop whatever the previous identity left behind,
        // then restore. No cloud profile → local stays empty and the
        // OnboardingGate routes this genuinely-new account to the concierge.
        clearLocalAccountState();
        const remote = await fetchMe<UserProfile & Record<string, unknown>>(userId);
        if (!cancelled && remote && typeof remote.completedAt === "number") {
          saveProfile(remote as UserProfile);
          restoreInteractionData(remote);
        }
        if (!cancelled) {
          window.dispatchEvent(new Event("giftmaxxing:profile"));
          window.dispatchEvent(new Event("giftmaxxing:interactions-restored"));
        }
      }
      if (!cancelled) setStateOwner(userId);
      settle();
    })();

    window.addEventListener("giftmaxxing:profile", push);
    window.addEventListener("giftmaxxing:interaction", push);
    return () => {
      cancelled = true;
      clearTimeout(safety);
      window.removeEventListener("giftmaxxing:profile", push);
      window.removeEventListener("giftmaxxing:interaction", push);
    };
  }, [isLoaded, isSignedIn, user]);

  return null;
}
