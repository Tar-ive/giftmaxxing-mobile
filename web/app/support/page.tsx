// Support page — the App Store Connect "Support URL" (Guideline 1.5) must point
// to a functional page where users can find help and contact us. Canonical URL:
// https://giftmaxxing-web.vercel.app/support. Static RSC, same conventions as
// app/privacy/page.tsx.
import Link from "next/link";

export const metadata = {
  title: "Support — Giftmaxxing",
  description: "Get help with Giftmaxxing: contact us, FAQs, account deletion, and privacy.",
};

const SUPPORT_EMAIL = "adhsaksham27@gmail.com";

export default function SupportPage() {
  return (
    <main className="mx-auto max-w-2xl px-5 py-16">
      <Link href="/" className="text-sm font-semibold text-coral hover:underline">
        ← Giftmaxxing
      </Link>
      <h1 className="mt-6 font-display text-3xl font-extrabold text-ink">Support</h1>
      <p className="mt-2 text-sm text-ink-faint">We&apos;re here to help.</p>

      <section className="mt-8 space-y-4 text-sm leading-relaxed text-ink-soft">
        <h2 className="pt-2 font-display text-xl font-bold text-ink">Contact us</h2>
        <p>
          Questions, feedback, or trouble with the app? Email us and we&apos;ll get back to
          you, usually within 1–2 business days:
        </p>
        <p>
          <a
            href={`mailto:${SUPPORT_EMAIL}?subject=Giftmaxxing%20Support`}
            className="font-semibold text-coral hover:underline"
          >
            {SUPPORT_EMAIL}
          </a>
        </p>

        <h2 className="pt-4 font-display text-xl font-bold text-ink">Frequently asked</h2>

        <div className="space-y-3">
          <p>
            <strong className="text-ink">What is Giftmaxxing?</strong>
            <br />
            A gifting app that helps you find, plan, and time thoughtful gifts for the
            people you care about — build gift boards, send a friend a swipe deck to learn
            what they&apos;d love, and never miss an occasion.
          </p>

          <p>
            <strong className="text-ink">How do I delete my account?</strong>
            <br />
            In the app, go to <strong className="text-ink">You → Account → Delete Account</strong>.
            After a confirmation step, your account and all associated data (profile, gift
            boards, pools, saved ideas, and connections) are permanently and immediately
            deleted. This cannot be undone, and it needs no email or phone call. Signing out
            (without deleting) only clears data on the current device and keeps your account.
          </p>

          <p>
            <strong className="text-ink">How is my data handled?</strong>
            <br />
            See our{" "}
            <Link href="/privacy" className="font-semibold text-coral hover:underline">
              Privacy Policy
            </Link>
            . In short: your data lives in our own AWS account, encrypted at rest, and is
            never sold. Sensitive identifiers are redacted before any text reaches our AI
            provider.
          </p>

          <p>
            <strong className="text-ink">Someone shared a swipe challenge with me — do I
            need an account?</strong>
            <br />
            No. You can swipe as a guest without signing up; see the{" "}
            <Link href="/privacy#recipient" className="font-semibold text-coral hover:underline">
              recipient section of our privacy policy
            </Link>{" "}
            for what&apos;s shared.
          </p>

          <p>
            <strong className="text-ink">How do group gifts and payments work?</strong>
            <br />
            Giftmaxxing helps you organize a group gift and invite people, but we do not
            process payments or hold funds — any money movement happens directly between you
            and the people you invite. See the{" "}
            <Link href="/privacy#group-gifts" className="font-semibold text-coral hover:underline">
              group gifts section
            </Link>
            .
          </p>
        </div>

        <h2 className="pt-4 font-display text-xl font-bold text-ink">Still stuck?</h2>
        <p>
          Email{" "}
          <a
            href={`mailto:${SUPPORT_EMAIL}?subject=Giftmaxxing%20Support`}
            className="font-semibold text-coral hover:underline"
          >
            {SUPPORT_EMAIL}
          </a>{" "}
          with a description of the problem (and your device + app version if it&apos;s a
          bug) and we&apos;ll help.
        </p>
      </section>
    </main>
  );
}
