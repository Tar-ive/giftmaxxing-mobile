import Image from "next/image";
import Link from "next/link";
import { ArrowDown, ArrowUpRight, Heart, ShieldCheck, Sparkles, Trophy, Users } from "lucide-react";
import { APP_STORE_URL } from "@/lib/app-links";
import styles from "./launch-page.module.css";

const brands = ["etsy", "target", "walmart", "nike", "shopify", "amazon"];

const AWARD = "Winner · Most Commercializable Hack";

const winners = [
  {
    name: "Saksham Adhikari",
    role: "Co-creator, Giftmaxxing",
    image: "/team/saksham.jpg",
  },
  {
    name: "Kusum Bhattarai Sharma",
    role: "Co-creator, Giftmaxxing",
    image: "/team/kusum.jpg",
  },
];

const screens = [
  {
    eyebrow: "Discover",
    title: "A feed that already knows their taste.",
    body: "Personalized finds, real products, and gift galleries for every kind of person.",
    image: "/appstore/home.png",
    alt: "Giftmaxxing Home feed with gift galleries and a product post",
  },
  {
    eyebrow: "Decide",
    title: "Swipe until the right gift feels obvious.",
    body: "Build a short list for yourself, someone you love, or the whole group.",
    image: "/appstore/swipe.png",
    alt: "Giftmaxxing Swipe screen showing a gift recommendation",
  },
  {
    eyebrow: "Curate",
    title: "Every occasion gets its own beautiful shelf.",
    body: "Browse thoughtful collections by recipient, moment, budget, and vibe.",
    image: "/appstore/gallery.png",
    alt: "Giftmaxxing anniversary gift gallery",
  },
  {
    eyebrow: "Together",
    title: "Birthdays, circles, and group gifts in one place.",
    body: "Remember the date, invite the people, pick together, and split the cost.",
    image: "/appstore/circles.png",
    alt: "Giftmaxxing Circles screen for dates and collaborative gift boards",
  },
];

export function LaunchPage() {
  return (
    <main className={styles.page}>
      <div className={styles.awardBar}>
        <div className={styles.awardBarInner}>
          <span className={styles.awardTag}>
            <Trophy aria-hidden="true" /> {AWARD}
          </span>
          <span className={styles.awardRule} aria-hidden="true" />
          <Image
            src="/award/h0-lockup.png"
            width={166}
            height={44}
            className={styles.awardLockup}
            alt="Vercel v0 and AWS"
          />
          <span className={styles.awardEvent}>H0: Hack the Zero Stack</span>
        </div>
      </div>

      <header className={styles.header}>
        <Link href="/" className={styles.brand} aria-label="Giftmaxxing home">
          <Image src="/app-icon-v2.png" width={38} height={38} alt="" priority />
          <span>giftmaxxing</span>
        </Link>
        <nav aria-label="Main navigation">
          <a href="#features">Features</a>
          <a href="#screens">Screens</a>
          <Link href="/privacy">Privacy</Link>
          <Link href="/support">Support</Link>
        </nav>
        <a
          href={APP_STORE_URL}
          className={styles.headerCta}
          target="_blank"
          rel="noopener noreferrer"
        >
          Out on the App Store
        </a>
      </header>

      <section className={styles.hero} aria-labelledby="hero-title">
        <div className={styles.heroCopy}>
          <p className={styles.kicker}>for iPhone · out now on the app store</p>
          <h1 id="hero-title">
            Know what they&apos;ll love.
            <span>Before you buy.</span>
          </h1>
          <p className={styles.lede}>
            One calm place to discover gifts, remember every moment, and pick together.
            Maxi makes thoughtful gifting feel effortless.
          </p>
          <div className={styles.heroActions}>
            <a
              href={APP_STORE_URL}
              className={styles.primaryButton}
              target="_blank"
              rel="noopener noreferrer"
            >
              Download on the App Store <ArrowUpRight aria-hidden="true" />
            </a>
            <a href="#screens" className={styles.textLink}>
              See the iPhone app <ArrowDown aria-hidden="true" />
            </a>
            <Link href="/feed" className={styles.textLink}>
              Try it on the web <ArrowUpRight aria-hidden="true" />
            </Link>
          </div>
        </div>

        <div className={styles.heroVisual} aria-label="Giftmaxxing iPhone app previews">
          <div className={`${styles.phone} ${styles.phoneBack}`}>
            <Image
              src="/appstore/swipe.png"
              fill
              sizes="(max-width: 720px) 44vw, 310px"
              alt="Giftmaxxing swipe screen"
              priority
            />
          </div>
          <div className={`${styles.phone} ${styles.phoneFront}`}>
            <Image
              src="/appstore/home.png"
              fill
              sizes="(max-width: 720px) 52vw, 350px"
              alt="Giftmaxxing home screen"
              priority
            />
          </div>
        </div>
      </section>

      <section className={styles.brandStrip} aria-label="Brands in the gift feed">
        <p>Real finds from brands people already love</p>
        <div className={styles.brandLogos}>
          {brands.map((brand) => (
            <span key={brand} className={styles.brandBubble}>
              <Image
                src={`/brands/${brand}.svg`}
                width={30}
                height={30}
                alt={brand[0].toUpperCase() + brand.slice(1)}
              />
            </span>
          ))}
        </div>
      </section>

      <section id="features" className={styles.statement}>
        <p className={styles.eyebrow}>Thoughtful, without the homework</p>
        <h2>
          Stop opening twenty tabs.
          <span>Start with the person.</span>
        </h2>
        <p>
          Giftmaxxing turns taste, relationships, occasions, and budget into a small
          set of gifts that actually make sense.
        </p>
        <div className={styles.featurePills}>
          <span><Sparkles aria-hidden="true" /> AI picks with a reason</span>
          <span><Heart aria-hidden="true" /> Shared wishlists</span>
          <span><Users aria-hidden="true" /> Group gifting</span>
          <span><ShieldCheck aria-hidden="true" /> Private by design</span>
        </div>
      </section>

      <section id="screens" className={styles.screens}>
        {screens.map((screen, index) => (
          <article className={styles.screenStory} key={screen.title}>
            <div className={styles.screenCopy}>
              <p className={styles.eyebrow}>{screen.eyebrow}</p>
              <h2>{screen.title}</h2>
              <p>{screen.body}</p>
              <span className={styles.step}>0{index + 1}</span>
            </div>
            <div className={styles.screenStage}>
              <div className={styles.screenPhone}>
                <Image
                  src={screen.image}
                  fill
                  sizes="(max-width: 720px) 76vw, 390px"
                  alt={screen.alt}
                />
              </div>
            </div>
          </article>
        ))}
      </section>

      <section id="launch" className={styles.launch}>
        <Image
          src="/app-icon-v2.png"
          width={88}
          height={88}
          className={styles.appIcon}
          alt="Giftmaxxing app icon"
        />
        <p className={styles.eyebrow}>Out now on the App Store</p>
        <h2>Your next great gift is one download away.</h2>
        <p>
          Giftmaxxing for iPhone is live. Download it free, or start on the web
          and pick up where you left off.
        </p>
        <div className={styles.launchActions}>
          <a
            href={APP_STORE_URL}
            className={styles.primaryButton}
            target="_blank"
            rel="noopener noreferrer"
          >
            Download on the App Store <ArrowUpRight aria-hidden="true" />
          </a>
          <Link href="/feed" className={styles.secondaryButton}>Try it on the web</Link>
        </div>
      </section>

      <footer className={styles.footer}>
        <section className={styles.winners} aria-labelledby="winners-title">
          <p className={styles.winnersEyebrow}>
            <Trophy aria-hidden="true" /> {AWARD}
          </p>
          <h2 id="winners-title">Meet the winners.</h2>
          <p className={styles.winnersLede}>
            Giftmaxxing was built at H0 and took home Most Commercializable Hack.
            The same two people still ship every release.
          </p>
          <Image
            src="/award/h0-banner.png"
            width={990}
            height={96}
            className={styles.awardBanner}
            alt="H0: Hack the Zero Stack with Vercel v0 & AWS Databases"
          />
          <ul className={styles.winnerGrid}>
            {winners.map((winner) => (
              <li key={winner.name} className={styles.winner}>
                <Image
                  src={winner.image}
                  width={168}
                  height={168}
                  className={styles.winnerPhoto}
                  alt={winner.name}
                />
                <p className={styles.winnerName}>{winner.name}</p>
                <p className={styles.winnerRole}>{winner.role}</p>
              </li>
            ))}
          </ul>
        </section>

        <div className={styles.footerMeta}>
        <div className={styles.brand}>
          <Image src="/app-icon-v2.png" width={34} height={34} alt="" />
          <span>giftmaxxing</span>
        </div>
        <p>Thoughtful gifting, finally figured out.</p>
        <nav aria-label="Footer navigation">
          <Link href="/feed">Open web app</Link>
          <Link href="/terms">Terms</Link>
          <Link href="/privacy">Privacy</Link>
          <Link href="/support">Support</Link>
        </nav>
        <small>© 2026 Giftmaxxing</small>
        </div>
      </footer>
    </main>
  );
}
