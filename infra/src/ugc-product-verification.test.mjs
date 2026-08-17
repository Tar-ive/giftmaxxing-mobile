import test from "node:test";
import assert from "node:assert/strict";
import { productPipelineStatus, verifyProductLink } from "./ugc-product-verification.mjs";

const response = (html, status = 200) => new Response(html, { status, headers: { "content-type": "text/html" } });
const publicHost = async () => [{ address: "93.184.216.34", family: 4 }];

test("extracts grounded retailer evidence and a short description", async () => {
  const html = `<script type="application/ld+json">${JSON.stringify({
    "@type": "Product", name: "Trail Bottle", brand: { name: "Example" },
    description: "An insulated bottle made for long trail days.",
    image: ["https://cdn.example.com/one.jpg", "https://cdn.example.com/two.jpg"],
    offers: { price: "39.00", priceCurrency: "USD", availability: "https://schema.org/InStock" },
  })}</script>`;
  const out = await verifyProductLink({ name: "Bottle", url: "https://shop.example.com/trail" }, { fetchImpl: async () => response(html), resolveHost: publicHost });
  assert.equal(out.status, "EVIDENCE_READY");
  assert.equal(out.description, "An insulated bottle made for long trail days.");
  assert.equal(out.images.length, 2);
  assert.equal(out.price, 39);
});

test("fails closed without product evidence", async () => {
  const out = await verifyProductLink({ name: "Idea", url: "https://example.com/story" }, { fetchImpl: async () => response("<html></html>"), resolveHost: publicHost });
  assert.equal(out.status, "MANUAL_REVIEW_REQUIRED");
  assert.equal(productPipelineStatus([out], true), "MANUAL_REVIEW_REQUIRED");
});

test("rejects unsafe URLs", async () => {
  const out = await verifyProductLink({ url: "http://169.254.169.254/latest/meta-data" });
  assert.equal(out.status, "SOURCE_REJECTED");
});
