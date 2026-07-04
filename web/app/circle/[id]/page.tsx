import type { Metadata } from "next";
import { CircleClient } from "./circle-client";

// The shareable circle page — family members open this straight from the
// group chat, so the link preview should say whose circle it is. The GET is
// public (link = credential), so we can fetch the name server-side.
export async function generateMetadata({
  params,
}: {
  params: Promise<{ id: string }>;
}): Promise<Metadata> {
  const { id } = await params;
  const base = process.env.NEXT_PUBLIC_API_URL ?? "";
  let name: string | null = null;
  if (base) {
    try {
      const res = await fetch(`${base}/circles/${encodeURIComponent(id)}`, {
        next: { revalidate: 60 },
      });
      if (res.ok) {
        const data = (await res.json()) as { circle?: { name?: string } };
        name = data.circle?.name ?? null;
      }
    } catch {
      // preview falls back to the generic title
    }
  }
  const title = name ? `${name} — gift circle` : "Gift circle";
  return {
    title,
    description:
      "Add your birthday to the circle so nobody misses a gift moment. No sign-up needed.",
    openGraph: {
      title,
      description: "One shared calendar of birthdays and gift moments for the whole group.",
    },
  };
}

export default async function CirclePage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  return <CircleClient circleId={id} />;
}
