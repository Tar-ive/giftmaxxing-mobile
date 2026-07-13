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
