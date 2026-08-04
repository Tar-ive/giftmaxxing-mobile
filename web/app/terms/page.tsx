import Link from "next/link";

export const metadata = {
  title: "Terms of Service — Giftmaxxing",
  description: "The terms that apply when you use Giftmaxxing.",
};

const SUPPORT_EMAIL = "adhsaksham27@gmail.com";

export default function TermsPage() {
  return (
    <main className="mx-auto max-w-2xl px-5 py-16">
      <Link href="/" className="text-sm font-semibold text-coral hover:underline">
        ← Giftmaxxing
      </Link>
      <h1 className="mt-6 font-display text-3xl font-extrabold text-ink">
        Terms of Service
      </h1>
      <p className="mt-2 text-sm text-ink-faint">Last updated August 4, 2026</p>

      <section className="mt-8 space-y-4 text-sm leading-relaxed text-ink-soft">
        <p>
          These Terms of Service govern your use of the Giftmaxxing mobile app,
          website, and related services. By using Giftmaxxing, you agree to these
          terms and our{" "}
          <Link href="/privacy" className="font-semibold text-coral hover:underline">
            Privacy Policy
          </Link>
          . If you do not agree, do not use the service.
        </p>

        <h2 className="pt-4 font-display text-xl font-bold text-ink">Who may use Giftmaxxing</h2>
        <p>
          You must be legally able to agree to these terms. If you use Giftmaxxing
          for an organization, you confirm that you are authorized to accept these
          terms for it. You are responsible for your account and for keeping your
          sign-in credentials secure.
        </p>

        <h2 className="pt-4 font-display text-xl font-bold text-ink">What Giftmaxxing provides</h2>
        <p>
          Giftmaxxing helps people discover gift ideas, create gift boards, remember
          occasions, share swipe challenges, organize group gifts, and publish content
          they choose to connected services. Recommendations are suggestions, not
          guarantees that a product, price, delivery date, or recipient preference is
          accurate or available.
        </p>

        <h2 className="pt-4 font-display text-xl font-bold text-ink">Purchases and third parties</h2>
        <p>
          Products are sold by third-party retailers, not Giftmaxxing. Their prices,
          availability, shipping, returns, warranties, and terms control your purchase.
          Some links may be affiliate links, which means Giftmaxxing may earn a
          commission without changing your price.
        </p>

        <h2 className="pt-4 font-display text-xl font-bold text-ink">Group gifts</h2>
        <p>
          Giftmaxxing can help people coordinate a group gift, but it does not process
          payments, hold funds, or settle contributions. Participants are responsible
          for any payments, refunds, chargebacks, or disputes between them.
        </p>

        <h2 className="pt-4 font-display text-xl font-bold text-ink">Your content</h2>
        <p>
          You keep ownership of content you submit. You give Giftmaxxing permission to
          host, process, display, and transmit that content only as needed to operate
          features you use, including sharing or publishing content when you explicitly
          request it. You must have the rights needed to submit and share that content.
        </p>

        <h2 className="pt-4 font-display text-xl font-bold text-ink">Connected services</h2>
        <p>
          If you connect a third-party account, such as TikTok, you authorize
          Giftmaxxing to use the permissions you approve for the actions you request.
          Third-party services have their own terms and privacy practices. You can
          revoke their access through the connected service or your Giftmaxxing account
          settings when that option is available.
        </p>

        <h2 className="pt-4 font-display text-xl font-bold text-ink">Acceptable use</h2>
        <p>You may not use Giftmaxxing to:</p>
        <ul className="list-disc space-y-1 pl-5">
          <li>break the law, infringe another person&apos;s rights, or facilitate fraud;</li>
          <li>upload harmful, deceptive, abusive, or unauthorized content;</li>
          <li>access accounts or data without permission;</li>
          <li>interfere with, overload, reverse engineer, or bypass service protections; or</li>
          <li>use automated access except through interfaces Giftmaxxing expressly provides.</li>
        </ul>

        <h2 className="pt-4 font-display text-xl font-bold text-ink">Service changes and termination</h2>
        <p>
          We may change, suspend, or discontinue features and may restrict accounts that
          violate these terms or create risk for users or the service. You may stop using
          Giftmaxxing at any time and can delete your account from the app.
        </p>

        <h2 className="pt-4 font-display text-xl font-bold text-ink">Disclaimers and liability</h2>
        <p>
          Giftmaxxing is provided on an “as is” and “as available” basis to the extent
          permitted by law. We do not promise uninterrupted operation or that every
          recommendation or third-party listing is complete or error-free. To the extent
          permitted by law, Giftmaxxing is not liable for indirect, incidental, special,
          consequential, or punitive damages, or for losses caused by third-party products,
          retailers, services, or user conduct. Rights that cannot legally be waived remain
          unaffected.
        </p>

        <h2 className="pt-4 font-display text-xl font-bold text-ink">Changes to these terms</h2>
        <p>
          We may update these terms as Giftmaxxing changes. We will update the date above
          and provide additional notice when required. Continued use after an update means
          you accept the revised terms.
        </p>

        <h2 className="pt-4 font-display text-xl font-bold text-ink">Contact</h2>
        <p>
          Questions about these terms? Email{" "}
          <a
            href={`mailto:${SUPPORT_EMAIL}?subject=Giftmaxxing%20Terms`}
            className="font-semibold text-coral hover:underline"
          >
            {SUPPORT_EMAIL}
          </a>
          .
        </p>
      </section>
    </main>
  );
}
