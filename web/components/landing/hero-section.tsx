"use client";

import { useEffect, useState, useRef } from "react";
import Link from "next/link";
import { ArrowRight } from "lucide-react";

const words = ["love", "treasure", "remember", "show off"];

function BlurWord({ word, trigger }: { word: string; trigger: number }) {
  const letters = word.split("");
  const STAGGER = 45;      // ms between each letter
  const DURATION = 500;    // blur+opacity fade duration per letter
  const GRADIENT_HOLD = STAGGER * letters.length + DURATION + 200;

  const [letterStates, setLetterStates] = useState<{ opacity: number; blur: number }[]>(
    letters.map(() => ({ opacity: 0, blur: 20 }))
  );
  const [showGradient, setShowGradient] = useState(true);
  const framesRef = useRef<number[]>([]);
  const timersRef = useRef<ReturnType<typeof setTimeout>[]>([]);

  useEffect(() => {
    // reset
    framesRef.current.forEach(cancelAnimationFrame);
    timersRef.current.forEach(clearTimeout);
    framesRef.current = [];
    timersRef.current = [];

    // eslint-disable-next-line react-hooks/set-state-in-effect -- animation reset requires imperative state init
    setLetterStates(letters.map(() => ({ opacity: 0, blur: 20 })));
    setShowGradient(true);

    // stagger each letter
    letters.forEach((_, i) => {
      const t = setTimeout(() => {
        const start = performance.now();
        const tick = (now: number) => {
          const progress = Math.min((now - start) / DURATION, 1);
          const eased = 1 - Math.pow(1 - progress, 3);
          setLetterStates(prev => {
            const next = [...prev];
            next[i] = { opacity: eased, blur: 20 * (1 - eased) };
            return next;
          });
          if (progress < 1) {
            const id = requestAnimationFrame(tick);
            framesRef.current.push(id);
          }
        };
        const id = requestAnimationFrame(tick);
        framesRef.current.push(id);
      }, i * STAGGER);
      timersRef.current.push(t);
    });

    // remove gradient once all letters are settled
    const gt = setTimeout(() => setShowGradient(false), GRADIENT_HOLD);
    timersRef.current.push(gt);

    return () => {
      framesRef.current.forEach(cancelAnimationFrame);
      timersRef.current.forEach(clearTimeout);
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [trigger]);

  // gradient colours cycling across letter positions (Giftmaxxing warm palette)
  const gradientColors = ["#fb6f52", "#ff9a76", "#ffc2d1", "#ffc24b", "#fb6f52"];

  return (
    <>
      {letters.map((char, i) => {
        const colorIndex = (i / Math.max(letters.length - 1, 1)) * (gradientColors.length - 1);
        const lower = Math.floor(colorIndex);
        const upper = Math.min(lower + 1, gradientColors.length - 1);
        const t = colorIndex - lower;

        // lerp hex colours
        const hex2rgb = (hex: string) => {
          const r = parseInt(hex.slice(1, 3), 16);
          const g = parseInt(hex.slice(3, 5), 16);
          const b = parseInt(hex.slice(5, 7), 16);
          return [r, g, b];
        };
        const [r1, g1, b1] = hex2rgb(gradientColors[lower]);
        const [r2, g2, b2] = hex2rgb(gradientColors[upper]);
        const r = Math.round(r1 + (r2 - r1) * t);
        const g = Math.round(g1 + (g2 - g1) * t);
        const b = Math.round(b1 + (b2 - b1) * t);

        return (
          <span
            key={i}
            style={{
              display: "inline-block",
              opacity: letterStates[i]?.opacity ?? 0,
              filter: `blur(${letterStates[i]?.blur ?? 20}px)`,
              color: showGradient ? `rgb(${r},${g},${b})` : "#fb6f52",
              transition: "color 0.4s ease",
            }}
          >
            {char}
          </span>
        );
      })}
    </>
  );
}

export function HeroSection() {
  const [isVisible, setIsVisible] = useState(false);
  const [wordIndex, setWordIndex] = useState(0);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- hydration animation trigger
    setIsVisible(true);
  }, []);

  useEffect(() => {
    const interval = setInterval(() => {
      setWordIndex((prev) => (prev + 1) % words.length);
    }, 2500);
    return () => clearInterval(interval);
  }, []);

  return (
    <section className="relative min-h-screen flex flex-col justify-center items-start overflow-hidden bg-background">
      {/* Background image (Midjourney) with warm gradient fallback */}
      <div
        className="absolute inset-0 z-0"
        style={{
          background:
            "radial-gradient(120% 120% at 80% 25%, rgba(251,111,82,0.16), transparent 55%), radial-gradient(90% 90% at 95% 8%, rgba(255,194,75,0.14), transparent 50%), #f7f2eb",
        }}
      >
        <img
          src="https://cdn.midjourney.com/5a63ddac-c6a0-48f2-86b4-cd48e8ba610f/0_3.jpeg"
          alt=""
          aria-hidden="true"
          onError={(e) => {
            (e.currentTarget as HTMLImageElement).style.display = "none";
          }}
          className="w-full h-full object-cover object-center opacity-90"
        />
        {/* Cream overlays keep the left text crisp and blend the image edges */}
        <div className="absolute inset-0 bg-gradient-to-r from-[#f7f2eb] via-[#f7f2eb]/75 to-transparent" />
        <div className="absolute inset-0 bg-gradient-to-b from-[#f7f2eb]/50 via-transparent to-[#f7f2eb]/70" />
      </div>

      {/* Subtle grid lines */}
      <div className="absolute inset-0 z-[2] overflow-hidden pointer-events-none opacity-20">
        {[...Array(8)].map((_, i) => (
          <div
            key={`h-${i}`}
            className="absolute h-px bg-foreground/5"
            style={{
              top: `${12.5 * (i + 1)}%`,
              left: 0,
              right: 0,
            }}
          />
        ))}
        {[...Array(12)].map((_, i) => (
          <div
            key={`v-${i}`}
            className="absolute w-px bg-foreground/5"
            style={{
              left: `${8.33 * (i + 1)}%`,
              top: 0,
              bottom: 0,
            }}
          />
        ))}
      </div>
      
      <div className="relative z-10 w-full max-w-[1400px] mx-auto px-6 lg:px-12 py-32 lg:py-40">
        <div className="lg:max-w-[55%]">
        {/* Eyebrow */}
        <div 
          className={`mb-8 transition-all duration-700 ${
            isVisible ? "opacity-100 translate-y-0" : "opacity-0 translate-y-4"
          }`}
        >
          <span className="inline-flex items-center gap-3 text-sm font-mono text-muted-foreground">
            <span className="w-8 h-px bg-foreground/30" />
            Social gifting, powered by Maxi · iOS launching soon
          </span>
        </div>
        
        {/* Main headline */}
        <div className="mb-6">
          <h1 
            className={`text-left text-[clamp(2rem,6vw,7rem)] font-display leading-[0.92] tracking-tight text-foreground transition-all duration-1000 ${
              isVisible ? "opacity-100 translate-y-0" : "opacity-0 translate-y-8"
            }`}
          >
            <span className="block whitespace-nowrap">Know exactly what</span>
            <span className="block whitespace-nowrap">
              they&apos;ll{" "}
              <span className="relative inline-block">
                <BlurWord word={words[wordIndex]} trigger={wordIndex} />
              </span>
            </span>
          </h1>
        </div>

        <p
          className={`mb-12 max-w-md text-base sm:text-lg text-muted-foreground leading-relaxed transition-all duration-700 delay-150 ${
            isVisible ? "opacity-100 translate-y-0" : "opacity-0 translate-y-4"
          }`}
        >
          Try Giftmaxxing on the web today — our iOS app is launching soon on the App Store.
        </p>

        {/* Dual CTA */}
        <div
          className={`flex flex-col sm:flex-row items-start gap-4 transition-all duration-700 delay-300 ${
            isVisible ? "opacity-100 translate-y-0" : "opacity-0 translate-y-4"
          }`}
        >
          <Link
            href="/feed"
            className="inline-flex items-center gap-2 bg-[#fb6f52] hover:bg-[#fb6f52]/90 text-white font-semibold px-8 h-14 rounded-full text-base transition-colors group"
          >
            Try it now
            <ArrowRight className="w-4 h-4 transition-transform group-hover:translate-x-1" />
          </Link>
          <Link
            href="/gift"
            className="inline-flex items-center gap-2 border border-foreground/20 hover:border-foreground/40 bg-background/60 backdrop-blur-sm text-foreground font-semibold px-8 h-14 rounded-full text-base transition-colors"
          >
            🎁 Find a gift in 60 seconds
          </Link>
          <Link
            href="/challenge"
            className="inline-flex items-center gap-2 text-foreground/70 hover:text-foreground font-semibold px-4 h-14 rounded-full text-base transition-colors"
          >
            or share a challenge
          </Link>
        </div>
        </div>
      </div>
      
      {/* Stats — 3 metrics static, no auto-scroll */}
      <div 
        className={`absolute bottom-12 left-0 right-0 px-6 lg:px-12 transition-all duration-700 delay-500 ${
          isVisible ? "opacity-100" : "opacity-0"
        }`}
      >
        <div className="max-w-[1400px] mx-auto flex items-start gap-10 lg:gap-20">
          {[
            { value: "12k+", label: "finds shared by friends" },
            { value: "0", label: "double-bought gifts" },
            { value: "4.9\u2605", label: "gifts they actually loved" },
          ].map((stat) => (
            <div key={stat.label} className="flex flex-col gap-2">
              <span className="text-3xl lg:text-4xl font-display text-foreground">{stat.value}</span>
              <span className="text-xs text-muted-foreground leading-tight">
                {stat.label}
              </span>
            </div>
          ))}
        </div>
      </div>

      {/* Scroll indicator */}

    </section>
  );
}
