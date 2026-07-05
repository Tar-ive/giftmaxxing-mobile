"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { Avatar, Icons, Maxi } from "@/components/ui";
import { useCurrentUser } from "@/lib/identity";
import { useMaxi } from "@/components/app/maxi-provider";
import { Show, SignInButton, UserButton } from "@clerk/nextjs";
import { localUnseenCount, LOCAL_CONN_EVENT } from "@/lib/local-connections";

const ACTIVITY_SEEN_KEY = "giftmaxxing_activity_seen";
const ACTIVITY_UNSEEN_COUNT = 3; // demo unseen count

function useUnseenActivity(): number {
  const [count, setCount] = useState(0);
  const pathname = usePathname();
  useEffect(() => {
    const check = () => {
      try {
        const seen = localStorage.getItem(ACTIVITY_SEEN_KEY);
        const demoCount = seen ? 0 : ACTIVITY_UNSEEN_COUNT;
        const connCount = localUnseenCount();
        setCount(demoCount + connCount);
      } catch {
        setCount(0);
      }
    };
    check();
    window.addEventListener("giftmaxxing:activity-seen", check);
    window.addEventListener("storage", check);
    window.addEventListener(LOCAL_CONN_EVENT, check);
    return () => {
      window.removeEventListener("giftmaxxing:activity-seen", check);
      window.removeEventListener("storage", check);
      window.removeEventListener(LOCAL_CONN_EVENT, check);
    };
  }, [pathname]);
  return count;
}

const clerkEnabled = !!process.env.NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY;

type Item = {
  label: string;
  href: string;
  icon: keyof typeof Icons;
  activeIcon?: keyof typeof Icons;
};

const ITEMS: Item[] = [
  { label: "Home", href: "/feed", icon: "home", activeIcon: "homeFill" },
  { label: "Search", href: "/feed/search", icon: "search" },
  { label: "Concierge", href: "/gift", icon: "sparkle" },
  { label: "Swipe", href: "/feed/swipe", icon: "cards" },
  { label: "Events", href: "/feed/events", icon: "calendar" },
  { label: "Shop", href: "/feed/shop", icon: "gift" },
  { label: "Gifts", href: "/feed/pools", icon: "users" },
  { label: "Messages", href: "/feed/messages", icon: "message" },
  { label: "Notifications", href: "/feed/activity", icon: "heart" },
];

export function Sidebar() {
  const pathname = usePathname();
  const { setCartOpen, cartCount } = useMaxi();
  const unseenActivity = useUnseenActivity();

  return (
    <aside className="sticky top-0 hidden h-screen shrink-0 flex-col border-r border-line bg-cream/80 px-3 py-6 backdrop-blur-xl md:flex md:w-[76px] xl:w-64 xl:px-4">
      <Link href="/feed" className="mb-8 flex items-center gap-2 px-2">
        <Maxi size={34} />
        <span className="hidden font-display text-xl font-extrabold tracking-tight text-ink xl:block">
          Giftmaxxing
        </span>
      </Link>

      <nav className="flex flex-1 flex-col gap-1">
        {ITEMS.map((it) => {
          const active = pathname === it.href;
          const Ico = Icons[active && it.activeIcon ? it.activeIcon : it.icon];
          const badge = it.href === "/feed/activity" ? unseenActivity : 0;
          return (
            <Link
              key={it.label}
              href={it.href}
              className={`flex items-center gap-4 rounded-xl px-3 py-3 transition-colors hover:bg-ink/5 ${
                active ? "font-bold text-ink" : "font-medium text-ink"
              }`}
            >
              <span className="relative">
                <Ico size={26} />
                {badge > 0 && (
                  <span className="absolute -right-1.5 -top-1.5 grid h-[18px] min-w-[18px] place-items-center rounded-full bg-coral px-1 text-[10px] font-bold text-white">
                    {badge}
                  </span>
                )}
              </span>
              <span className="hidden xl:block">{it.label}</span>
            </Link>
          );
        })}

        <Link
          href="/feed/maxi"
          className={`flex items-center gap-4 rounded-xl px-3 py-3 transition-colors hover:bg-coral-soft ${
            pathname === "/feed/maxi" ? "font-bold" : "font-medium"
          } text-ink`}
        >
          <span className="grid h-[26px] w-[26px] place-items-center">
            <Maxi size={26} />
          </span>
          <span className="hidden items-center gap-2 xl:flex">
            Ask Maxi
            <span className="rounded-full bg-coral px-1.5 py-0.5 text-[10px] font-bold text-white">
              AI
            </span>
          </span>
        </Link>

        <button
          type="button"
          onClick={() => setCartOpen(true)}
          className="flex items-center gap-4 rounded-xl px-3 py-3 text-left transition-colors hover:bg-ink/5 text-ink"
        >
          <span className="relative grid h-[26px] w-[26px] place-items-center">
            <Icons.cart size={26} />
            {cartCount > 0 && (
              <span className="absolute -right-1.5 -top-1.5 grid h-4 min-w-4 place-items-center rounded-full bg-coral px-1 text-[10px] font-bold text-white">
                {cartCount}
              </span>
            )}
          </span>
          <span className="hidden xl:block">Cart</span>
        </button>
      </nav>
    </aside>
  );
}

/* Items shown in the mobile "More" drawer (not in the bottom tab bar) */
const DRAWER_ITEMS: Item[] = [
  { label: "Concierge", href: "/gift", icon: "sparkle" },
  { label: "Swipe", href: "/feed/swipe", icon: "cards" },
  { label: "Shop", href: "/feed/shop", icon: "gift" },
  { label: "Gifts", href: "/feed/pools", icon: "users" },
  { label: "Cart", href: "/feed/cart", icon: "cart" },
];

/* Mobile top + bottom bars (Instagram mobile web) */
export function MobileBars() {
  const pathname = usePathname();
  const me = useCurrentUser();
  const [drawerOpen, setDrawerOpen] = useState(false);
  const unseenActivity = useUnseenActivity();

  const tabs: Item[] = [
    { label: "Home", href: "/feed", icon: "home", activeIcon: "homeFill" },
    { label: "Search", href: "/feed/search", icon: "search" },
    { label: "Events", href: "/feed/events", icon: "calendar" },
    { label: "Menu", href: "#menu", icon: "menu" },
    { label: "Profile", href: "/feed/you", icon: "home" },
  ];

  return (
    <>
      {/* Top header */}
      <div className="sticky top-0 z-30 flex items-center justify-between border-b border-line bg-cream/85 px-4 py-3 backdrop-blur-xl md:hidden">
        <Link href="/feed" className="flex items-center gap-2">
          <Maxi size={28} />
          <span className="font-display text-lg font-extrabold text-ink">Giftmaxxing</span>
        </Link>
        <div className="flex items-center gap-4 text-ink">
          <Link href="/feed/activity" className="relative">
            <Icons.heart size={24} />
            {unseenActivity > 0 && (
              <span className="absolute -right-1.5 -top-1.5 grid h-[16px] min-w-[16px] place-items-center rounded-full bg-coral px-1 text-[9px] font-bold text-white">
                {unseenActivity}
              </span>
            )}
          </Link>
          <Link href="/feed/messages"><Icons.message size={24} /></Link>
          {clerkEnabled && (
            <>
              <Show when="signed-in">
                <UserButton />
              </Show>
              <Show when="signed-out">
                <SignInButton mode="modal">
                  <button className="text-sm font-bold text-coral">Sign in</button>
                </SignInButton>
              </Show>
            </>
          )}
        </div>
      </div>

      {/* Bottom tab bar */}
      <nav className="fixed bottom-0 left-0 right-0 z-30 flex items-center justify-around border-t border-line bg-cream/90 px-2 py-2.5 backdrop-blur-xl md:hidden">
        {tabs.map((t) => {
          const isProfile = t.label === "Profile";
          const isMenu = t.label === "Menu";

          if (isProfile)
            return (
              <Link key={t.label} href={t.href}>
                <Avatar grad={me.grad} label={me.name} size={26} />
              </Link>
            );

          if (isMenu)
            return (
              <button
                type="button"
                key={t.label}
                aria-label="Open navigation menu"
                aria-expanded={drawerOpen}
                aria-controls="mobile-nav-drawer"
                className="text-ink"
                onClick={() => setDrawerOpen(true)}
              >
                <Icons.menu size={26} />
              </button>
            );

          const active = pathname === t.href;
          const Ico = Icons[active && t.activeIcon ? t.activeIcon : t.icon];
          return (
            <Link key={t.label} href={t.href} className="text-ink">
              <Ico size={26} />
            </Link>
          );
        })}
      </nav>

      {/* Mobile navigation drawer (bottom sheet) */}
      {drawerOpen && (
        <div
          className="fixed inset-0 z-50 md:hidden"
          role="dialog"
          aria-modal="true"
          aria-label="Navigation menu"
        >
          {/* Backdrop */}
          <button
            type="button"
            aria-label="Close navigation menu"
            className="absolute inset-0 bg-ink/40 backdrop-blur-sm"
            onClick={() => setDrawerOpen(false)}
          />
          {/* Sheet */}
          <div
            id="mobile-nav-drawer"
            className="absolute bottom-0 left-0 right-0 animate-rise rounded-t-3xl border-t border-line bg-cream pb-8 pt-3 shadow-xl"
          >
            {/* Close button */}
            <button
              type="button"
              aria-label="Close navigation menu"
              className="absolute right-4 top-3 text-ink"
              onClick={() => setDrawerOpen(false)}
            >
              <Icons.close size={20} />
            </button>
            {/* Handle */}
            <div className="mx-auto mb-4 h-1 w-10 rounded-full bg-ink/20" />
            <nav className="grid grid-cols-3 gap-2 px-4">
              {DRAWER_ITEMS.map((it) => {
                const active = pathname === it.href;
                const Ico = Icons[it.icon];
                return (
                  <Link
                    key={it.label}
                    href={it.href}
                    onClick={() => setDrawerOpen(false)}
                    className={`flex flex-col items-center gap-1.5 rounded-2xl px-2 py-3 transition-colors ${
                      active ? "bg-coral/10 font-bold text-coral" : "text-ink hover:bg-ink/5"
                    }`}
                  >
                    <Ico size={24} />
                    <span className="text-[11px] font-medium">{it.label}</span>
                  </Link>
                );
              })}
              {/* Ask Maxi */}
              <Link
                href="/feed/maxi"
                onClick={() => setDrawerOpen(false)}
                className={`flex flex-col items-center gap-1.5 rounded-2xl px-2 py-3 transition-colors ${
                  pathname === "/feed/maxi" ? "bg-coral/10 font-bold text-coral" : "text-ink hover:bg-ink/5"
                }`}
              >
                <Maxi size={24} />
                <span className="text-[11px] font-medium">Ask Maxi</span>
              </Link>
            </nav>
          </div>
        </div>
      )}
    </>
  );
}
