// PRIVACY-GUARD-DO-NOT-DELETE — This page is a required, user-mandated data-protection
// statement. Do NOT delete it, empty it, or remove this marker / the "How we protect
// your data" section. Enforced by CI (.github/workflows/ci.yml); linked from the invite
// flow (/privacy#sender, /privacy#recipient).
import Link from "next/link";

export const metadata = {
  title: "Privacy — Giftmaxxing",
  description: "How Giftmaxxing handles your data, including soft profiles from the swipe challenge.",
};

export default function PrivacyPage() {
  return (
    <main className="mx-auto max-w-2xl px-5 py-16">
      <Link href="/" className="text-sm font-semibold text-coral hover:underline">
        ← Giftmaxxing
      </Link>
      <h1 className="mt-6 font-display text-3xl font-extrabold text-ink">Privacy</h1>
      <p className="mt-2 text-sm text-ink-faint">Last updated July 2026</p>

      <section className="mt-8 space-y-4 text-sm leading-relaxed text-ink-soft">
        <p>
          Giftmaxxing helps you find and time gifts for the people you care about. We
          store your profile, the people you shop for, and the dates you care about so
          your recommendations and reminders work across your devices.
        </p>

        <h2 className="pt-4 font-display text-xl font-bold text-ink">How we protect your data</h2>
        <p>
          We take very high precaution whenever we store your data. Everything is kept
          inside our own AWS account, <strong className="text-ink">encrypted at rest</strong>,
          behind least-privilege access controls. We never sell or rent your data.
        </p>
        <p>
          <strong className="text-ink">Scrubbed before AI.</strong> Before any text is sent
          to our AI provider (Amazon Bedrock, which powers Maxi and visual search), we
          automatically redact sensitive personal identifiers — such as{" "}
          <strong className="text-ink">email addresses, phone numbers, and payment or ID
          numbers</strong> — so they never leave for the model.
        </p>
        <p>
          <strong className="text-ink">No third party touches it.</strong> Amazon Bedrock
          processes requests inside our AWS account. Per AWS, your prompts and responses are{" "}
          <strong className="text-ink">not used to train any models</strong> and are{" "}
          <strong className="text-ink">not shared with the model provider or any third
          party</strong>.
        </p>
        <p>
          <strong className="text-ink">You have full ownership of your data.</strong> You can
          export or delete it at any time. Deleting your account removes your profile and
          sign-in identity (including the email links behind it), recipients, saved events,
          gift boards, connections and soft profiles you created, friends and direct
          messages, your group-gift contributions and chat messages, the swipe challenges
          you shared (including the responses collected through them), Maxi&apos;s memory of
          you, your analytics history, and your push-notification device tokens.
        </p>
        <p>
          <strong className="text-ink">What we keep, and for how long.</strong> Behavioral
          analytics from the app — things like taps, time spent on a card, and in-app search
          queries — are kept for <strong className="text-ink">at most 90 days</strong> and
          then expire automatically (immediately if you delete your account). Photos you
          submit for visual search are converted into a numeric taste vector used to find
          similar gifts; we keep that vector, not a browsable copy of your photo, and it is
          removed with your account too.
        </p>

        <h2 id="sender" className="scroll-mt-24 pt-4 font-display text-xl font-bold text-ink">
          If you shared a challenge (sender)
        </h2>
        <p>
          When you share a “swipe challenge” link and someone completes it, we create a{" "}
          <strong className="text-ink">soft profile</strong> on{" "}
          <strong className="text-ink">your</strong> account: the gift taste implied by
          their swipes, plus the name and any occasion or date <em>you</em> set when you
          shared the link. It is a <em>soft</em> profile — a lightweight record to help
          you gift them, not a full account — and it is visible only to you.
        </p>
        <p>
          By sharing the link you confirm the recipient is okay with it, and{" "}
          <strong className="text-ink">you take responsibility for the soft profile you
          create</strong> and for using it respectfully. You can delete it from your
          connections at any time.
        </p>

        <h2 id="recipient" className="scroll-mt-24 pt-4 font-display text-xl font-bold text-ink">
          If you received a challenge (recipient)
        </h2>
        <p>
          You don&apos;t need an account, and we don&apos;t ask you for your name or
          birthday. Swiping simply shares your{" "}
          <strong className="text-ink">gift taste</strong> (and the occasion the sender
          chose) with the person who invited you, so they can pick something you&apos;d
          actually love. Those matches become your gift set.
        </p>
        <p>
          You can ask the person who invited you to remove your soft profile at any time.
          We retain only what&apos;s needed to provide the feature.
        </p>

        <h2 id="group-gifts" className="scroll-mt-24 pt-4 font-display text-xl font-bold text-ink">
          Group gifts &amp; payments
        </h2>
        <p>
          Giftmaxxing lets you <strong className="text-ink">organize a group gift and invite
          people</strong> to it — in the app or by sharing a link. Anyone who opens an invite
          link must <strong className="text-ink">sign in and agree to these terms</strong> before
          they can take part.
        </p>
        <p>
          <strong className="text-ink">We do not process payments, hold funds, or manage how a
          group gift&apos;s cost is split.</strong> Any money movement happens directly between
          you and the people you invite, using whatever method you choose. You and your group are{" "}
          <strong className="text-ink">solely responsible</strong> for collecting, splitting, and
          settling contributions. Giftmaxxing is not a party to those transactions and takes no
          responsibility or liability for them — including amounts owed, refunds, chargebacks, or
          disputes between participants.
        </p>

        <h2 id="your-data" className="scroll-mt-24 pt-4 font-display text-xl font-bold text-ink">
          Export &amp; delete your data
        </h2>
        <p>
          You have full control over your data at any time. From your{" "}
          <Link href="/feed/settings" className="font-semibold text-coral hover:underline">
            Settings
          </Link>{" "}
          page you can:
        </p>
        <ul className="list-disc space-y-1 pl-5">
          <li>
            <strong className="text-ink">Download my data</strong> — export all your
            preferences, taste profile, saves, interactions, and other stored data as a
            JSON file.
          </li>
          <li>
            <strong className="text-ink">Delete all my data</strong> — permanently remove
            the locally stored profile, saved items, interaction history, cart, and related
            information. If you&apos;re signed in and the server is available, we also
            request server-side deletion, which covers everything listed under &ldquo;You
            have full ownership of your data&rdquo; above. In the iOS app, the same full
            deletion lives at You → Account → Delete Account.
          </li>
        </ul>
        <p>
          No waiting period, no hoops — your data is yours and you can take it or remove
          it whenever you choose.
        </p>

        <h2 className="pt-4 font-display text-xl font-bold text-ink">Your choices</h2>
        <p>
          You can edit or delete your profile, recipients, events, and connections from
          within the app. Questions? Reach out and we&apos;ll help.
        </p>

        <h2 className="pt-4 font-display text-xl font-bold text-ink">Contact</h2>
        <p>
          Questions about your privacy, or want to access or delete your data? Email us at{" "}
          <a
            href="mailto:adhsaksham27@gmail.com"
            className="font-semibold text-coral hover:underline"
          >
            adhsaksham27@gmail.com
          </a>{" "}
          and we&apos;ll help.
        </p>
      </section>
    </main>
  );
}
