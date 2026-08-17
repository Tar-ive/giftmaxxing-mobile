// node --test quality.test.mjs — parity contract with the iOS port
// (Giftmaxxing/Services/Recommendation/ContentQuality.swift). If these break,
// junk (auto parts, digital pattern files, listicles) leaks into the feed,
// recommendations, and visual search — or real gifts get dropped.
import test from "node:test";
import assert from "node:assert/strict";
import { classifyPin, isMajorUSRetailer } from "./quality.mjs";

test("replacement auto part with SKU prefix is non_gift (live feed example)", () => {
  const q = classifyPin({
    title: "Bm1240164 Replacement Front Driver Side Fender Fits 2014-2016 Bmw 428i",
    domain: "ebay.com",
    link: "https://www.ebay.com/itm/123",
    price: 89,
  });
  assert.equal(q.contentType, "non_gift");
  assert.equal(q.feedEligible, false);
  assert.equal(q.route, "drop");
});

test("washer fluid reservoir is non_gift despite retailer + price (live feed example)", () => {
  const q = classifyPin({
    title: "To1288213 Replacement Washer Fluid Reservoir Fits 2013-2018 Toyota Rav4",
    domain: "ebay.com",
    link: "https://www.ebay.com/itm/456",
    price: 49,
  });
  assert.equal(q.contentType, "non_gift");
  assert.equal(q.feedEligible, false);
});

test("door lock actuator is non_gift (live feed example)", () => {
  const q = classifyPin({
    title: "Door Lock Actuator Motor Dorman 937-080",
    domain: "ebay.com",
    price: 232,
  });
  assert.equal(q.contentType, "non_gift");
  assert.equal(q.feedEligible, false);
});

test("wheel stud with auto brand is non_gift (live feed example)", () => {
  const q = classifyPin({
    title: "Dorman 610368.1 Wheel Stud",
    domain: "ebay.com",
    price: 12,
  });
  assert.equal(q.contentType, "non_gift");
  assert.equal(q.feedEligible, false);
});

test("plumbing hardware is non_gift", () => {
  const q = classifyPin({
    title: "Kitchen Sink Strainer Drain Assembly, Stainless Steel",
    domain: "lowes.com",
    price: 18,
  });
  assert.equal(q.contentType, "non_gift");
  assert.equal(q.feedEligible, false);
});

test("digital PDF pattern is non_gift (live feed example)", () => {
  const q = classifyPin({
    title:
      "PDF File for Crochet Pattern (English), Junction Beanie, Pictures and Video Tutorials Included, Crochet Beanie Pattern",
    domain: "etsy.me",
    price: 7,
  });
  assert.equal(q.contentType, "non_gift");
  assert.equal(q.feedEligible, false);
});

test("instant-download printable is non_gift", () => {
  const q = classifyPin({
    title: "Boho Wall Art Set of 3, Instant Download, Printable",
    domain: "etsy.com",
    price: 5,
  });
  assert.equal(q.contentType, "non_gift");
});

test("real gift products stay eligible", () => {
  for (const title of [
    "Apple iPhone 16 (128 GB)",
    "Handmade Ceramic Coffee Mug",
    "Marigold Oval Bowl",
    "Weighted Blanket, 15 lbs",
    "LEGO Botanical Orchid Building Set",
    // Near-misses for the part patterns: giftable, must NOT be dropped.
    "Vintage Fender Stratocaster Miniature Guitar Model",
    "Crochet Beanie, Handmade Wool Hat",
  ]) {
    const q = classifyPin({ title, domain: "etsy.com", price: 30 });
    assert.equal(q.contentType, "single_product", `expected eligible: ${title}`);
    assert.equal(q.feedEligible, true, `expected eligible: ${title}`);
  }
});

test("a PRICE mentioning 'gift' is not a listicle (live AirPods regression)", () => {
  const q = classifyPin({
    title: "Open-ear comfort with real ANC — the under-$200 Apple gift.",
    domain: "amazon.com",
    price: 179,
  });
  assert.equal(q.contentType, "single_product");
  assert.equal(q.feedEligible, true);
});

test("EVERY curated catalog item is feed-eligible (server-side classify)", async () => {
  const { readFile } = await import("node:fs/promises");
  const { fileURLToPath } = await import("node:url");
  const { dirname, join } = await import("node:path");
  const dir = dirname(fileURLToPath(import.meta.url));
  const data = JSON.parse(await readFile(join(dir, "../ingest/catalog-basics.json"), "utf8"));
  for (const it of data.items) {
    const q = classifyPin({
      title: it.caption || it.name,
      domain: it.domain,
      link: it.link,
      price: it.price,
      giftType: it.giftType,
    });
    assert.equal(q.feedEligible, true, `${it.id} dropped: ${q.contentType} (${q.reasons.join(",")})`);
  }
});

test("curated services still bypass every gate", () => {
  const q = classifyPin({
    title: "Netflix Premium — 1 Year",
    domain: "youtube.com",
    giftType: "service",
  });
  assert.equal(q.contentType, "single_product");
  assert.equal(q.feedEligible, true);
});

test("listicles still route away from the feed", () => {
  const q = classifyPin({ title: "30 Birthday Gifts for The Friend with Elite Taste" });
  assert.equal(q.contentType, "gift_guide");
  assert.equal(q.feedEligible, false);
});

test("isMajorUSRetailer matches big-box domains incl. subdomains", () => {
  assert.equal(isMajorUSRetailer("amazon.com"), true);
  assert.equal(isMajorUSRetailer("www.target.com"), true);
  assert.equal(isMajorUSRetailer("walmart.com"), true);
  assert.equal(isMajorUSRetailer("shop.nordstrom.com"), true);
  assert.equal(isMajorUSRetailer("etsy.com"), false);
  assert.equal(isMajorUSRetailer("ebay.com"), false);
  assert.equal(isMajorUSRetailer(""), false);
});

// Supplies, fitments and event paper goods — everything below carries price +
// retailer + PDP path, so only the caption gate stops it. Every title here was
// observed live in the swipe deck.
test("classifyPin drops household supplies, tyres, fixtures and event stationery", () => {
  const junk = [
    "Zep Antibacterial 32 -fl oz Lemon Disinfectant Liquid All-Purpose Cleaner",
    'Fuel Maverick 15" Wheels Black 32" Outlaw Max Tires Honda Pioneer',
    "Gold Clothing Racks, Metal Clothes Rack With 8 Straight Arms",
    "We Couldn't Wait Reception Invitation - Elopement Announcement",
    "Tide Laundry Detergent 92 oz",
    "Save the Date Magnets",
    "Window Blinds 34in Cordless",
  ];
  for (const title of junk) {
    const r = classifyPin({ title, domain: "lowes.com", price: 25, link: "https://lowes.com/p/1" });
    assert.equal(r.feedEligible, false, `should drop: ${title}`);
    assert.equal(r.contentType, "non_gift", title);
  }
});

test("classifyPin keeps gifts the supply rules sit close to", () => {
  const keep = [
    "Thank You Card Set - letterpress",          // a boxed set IS a gift
    "Blind Box Mystery Figure - Series 3",       // not window blinds
    "Home made porcelain mug",
    "Turkish Rug Bench, Handmade Furniture, Living Room Bench",
    "Pebble Lighter - Exclusive - Rust",
    "Handknit Chunky Cardigan, Bubble Sleeves, Upcycled Yarn",
  ];
  for (const title of keep) {
    const r = classifyPin({ title, domain: "etsy.com", price: 40, link: "https://etsy.com/listing/1" });
    assert.equal(r.feedEligible, true, `should keep: ${title}`);
  }
});
