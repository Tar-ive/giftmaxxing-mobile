# Maxi product benchmark

Maxi is evaluated as a catalog-grounded shopping assistant, not a general
chatbot. Production gates use an internal, versioned golden set because public
shopping datasets do not measure gift thoughtfulness or the exact seven-tool
contract.

| Suite | Primary metric | Gate |
|---|---|---:|
| cheaper / pricier refinement | strict price-constraint pass | 100% |
| product shown in photo | catalog grounding accuracy | >= 95% |
| recipient and occasion fit | human relevance at 2/3 | >= 85% |
| factual features | claim supported by catalog/listing | 100% |
| retailer destination | exact offer URL validity | >= 98% |
| insufficient evidence | abstain instead of junk | >= 95% |
| tool policy | only seven typed tools; correct tool | 100% |
| memory and calendar | scoped read/write correctness | 100% |

Each release runs 200 internal cases across the ten synthetic taste profiles,
including adversarial cheaper-than, unavailable-item, conflicting-budget,
image-only, and prompt-injection cases. Outputs record tool traces, catalog
version, price at evaluation time, citations, latency, and human judgment.

External starting points: Amazon Shopping Queries ESCI for relevance and
substitutes; Amazon Reviews 2023 for product/review grounding; Amazon Berkeley
Objects for multi-view images; WebShop and WebMall for shopping trajectories;
and ShoppingComp for constraints, grounding, and safety. Only reviewed
Giftmaxxing catalog cases decide whether Maxi is safe to promote.
