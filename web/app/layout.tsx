import { ClerkProvider } from "@clerk/nextjs";
import type { Metadata } from "next";
import { AccountSync } from "@/components/app/account-sync";
import { AmazonOneLink } from "@/components/amazon-onelink";
import { Skimlinks } from "@/components/skimlinks";
import { Hanken_Grotesk, Instrument_Serif, Bricolage_Grotesque, JetBrains_Mono } from "next/font/google";
import "./globals.css";

const clerkEnabled = !!(
  process.env.NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY &&
  process.env.CLERK_SECRET_KEY
);

const hanken = Hanken_Grotesk({
  variable: "--font-hanken",
  subsets: ["latin"],
  weight: ["400", "500", "600", "700", "800"],
});

const instrument = Instrument_Serif({
  variable: "--font-instrument",
  subsets: ["latin"],
  weight: "400",
  style: ["normal", "italic"],
});

const bricolage = Bricolage_Grotesque({
  variable: "--font-bricolage",
  subsets: ["latin"],
  weight: ["400", "600", "700", "800"],
});

const jetbrains = JetBrains_Mono({
  variable: "--font-jetbrains",
  subsets: ["latin"],
  weight: ["400", "500"],
});

export const metadata: Metadata = {
  metadataBase: new URL("https://giftmaxxing.vercel.app"),
  title: "Giftmaxxing — thoughtful gifting, finally figured out",
  description:
    "Discover thoughtful gifts, remember every moment, and pick together. Giftmaxxing for iPhone is launching soon on the App Store.",
  applicationName: "Giftmaxxing",
  keywords: [
    "gifting",
    "gift ideas",
    "social gifting",
    "group gifting",
    "AI gift assistant",
    "wishlist",
    "Giftmaxxing",
  ],
  openGraph: {
    title: "Giftmaxxing — thoughtful gifting, finally figured out",
    description:
      "Know what they'll love before you buy. Giftmaxxing for iPhone is launching soon.",
    url: "https://giftmaxxing.vercel.app",
    siteName: "Giftmaxxing",
    type: "website",
    locale: "en_US",
  },
  twitter: {
    card: "summary_large_image",
    title: "Giftmaxxing — thoughtful gifting, finally figured out",
    description:
      "Know what they'll love before you buy. Giftmaxxing for iPhone is launching soon.",
  },
  icons: { icon: "/favicon.ico" },
  // Safari's native Smart App Banner ("Open in the Giftmaxxing app") on every
  // page, including shared invite links — the lowest-friction app conversion
  // surface iOS offers. No-op until the App Store id is configured.
  ...(process.env.NEXT_PUBLIC_APPLE_APP_ID
    ? { itunes: { appId: process.env.NEXT_PUBLIC_APPLE_APP_ID } }
    : {}),
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${hanken.variable} ${instrument.variable} ${bricolage.variable} ${jetbrains.variable} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col">
        {clerkEnabled ? (
          <ClerkProvider>
            <AccountSync />
            {children}
          </ClerkProvider>
        ) : (
          children
        )}
        <AmazonOneLink />
        <Skimlinks />
      </body>
    </html>
  );
}
