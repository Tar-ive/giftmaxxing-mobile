"use client";

// Onboarding IS the Gift Concierge.
//
// New users don't fill in a taste questionnaire about themselves — they meet
// Maxi and run their first real consult ("who are we gifting?") right away.
// The consult's answers double as the profile (deriveProfileFromConsult →
// saveProfile inside <GiftConsult onboarding/>), so the OnboardingGate, feed
// personalization, and DynamoDB sync all keep working on the same contract
// the old wizard used (UserProfile with ≥3 interests).
//
// "Skip for now" still saves a neutral profile — the gate must never loop a
// user who just wants to look around.

import { useCallback } from "react";
import { useRouter } from "next/navigation";
import { GiftConsult } from "@/components/app/gift-consult";
import { Maxi } from "@/components/ui";
import { getCurrentUser } from "@/lib/identity";
import { saveProfile } from "@/lib/onboarding";
import { deriveProfileFromConsult } from "@/lib/consult";

export default function OnboardingPage() {
  const router = useRouter();

  const skip = useCallback(() => {
    // A neutral consult → broad default profile (cozy/foodie/wellness pad).
    saveProfile(
      deriveProfileFromConsult(
        { relation: "other", occasion: "any", worlds: [], keeper: "light" },
        getCurrentUser().name,
      ),
    );
    router.push("/feed");
  }, [router]);

  return (
    <div className="mx-auto flex min-h-dvh max-w-2xl flex-col px-4 pb-6 pt-4 sm:px-6">
      <header className="mb-2 flex items-center justify-between">
        <div className="flex items-center gap-2.5">
          <Maxi size={34} />
          <div>
            <p className="font-display text-lg font-extrabold leading-none text-ink">Meet Maxi</p>
            <p className="text-[11px] font-medium text-ink-faint">your gift concierge</p>
          </div>
        </div>
        <button
          onClick={skip}
          className="rounded-full border border-line bg-surface px-4 py-2 text-xs font-bold text-ink-soft transition-colors hover:border-ink/25 hover:text-ink"
        >
          Skip for now
        </button>
      </header>

      <GiftConsult onboarding />
    </div>
  );
}
