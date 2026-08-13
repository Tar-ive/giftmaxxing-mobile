#!/usr/bin/env python3
import json, math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "Giftmaxxing/Resources/curated-gift-journeys.json"
MAP = ROOT / "docs/audits/carousel-theme-audit-2026-08-13/carousel-theme-map.json"
ASSETS = ROOT / "Giftmaxxing/Resources/Curated"
OUT = ROOT / "docs/audits/carousel-theme-audit-2026-08-13/tiles"
W, H, GAP = 420, 560, 24

def font(size, bold=False):
    paths = [Path("/System/Library/Fonts/SFNS.ttf"), Path("/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf")]
    for path in paths:
        if path.exists(): return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()

manifest = json.loads(MANIFEST.read_text())
typed = {x["id"]: x for x in json.loads(MAP.read_text())["carousels"]}
OUT.mkdir(parents=True, exist_ok=True)

def cover(journey):
    path = ASSETS / f'{journey["sourcePostId"]}-01.jpg'
    image = Image.open(path).convert("RGB") if path.exists() else Image.new("RGB", (W, H), "#eee")
    image = ImageOps.fit(image, (W, 420), method=Image.Resampling.LANCZOS)
    card = Image.new("RGB", (W, H), "white"); card.paste(image, (0, 0))
    draw = ImageDraw.Draw(card)
    assignment = typed[journey["id"]]
    draw.text((18, 438), journey["title"], fill="#10131a", font=font(24, True))
    draw.text((18, 476), assignment["filterLabel"], fill="#4f46cf", font=font(18, True))
    draw.text((18, 508), f'{assignment["themeId"]} · {journey["imageCount"]} slides · {len(journey["productIds"])} products', fill="#647083", font=font(14))
    return card

for page, start in enumerate(range(0, len(manifest["journeys"]), 12), 1):
    batch = manifest["journeys"][start:start + 12]
    canvas = Image.new("RGB", (GAP + 3 * (W + GAP), GAP + 4 * (H + GAP)), "#f4f6fa")
    for index, journey in enumerate(batch):
        canvas.paste(cover(journey), (GAP + (index % 3) * (W + GAP), GAP + (index // 3) * (H + GAP)))
    canvas.save(OUT / f"all-carousels-{page}.jpg", quality=90)

by_theme = {}
for journey in manifest["journeys"]:
    by_theme.setdefault(typed[journey["id"]]["themeId"], []).append(journey)
for theme_id, journeys in by_theme.items():
    cols, rows = min(3, len(journeys)), math.ceil(len(journeys) / min(3, len(journeys)))
    canvas = Image.new("RGB", (GAP + cols * (W + GAP), GAP + rows * (H + GAP)), "#f4f6fa")
    for index, journey in enumerate(journeys):
        canvas.paste(cover(journey), (GAP + (index % cols) * (W + GAP), GAP + (index // cols) * (H + GAP)))
    canvas.save(OUT / f"theme-{theme_id}.jpg", quality=90)
print(json.dumps({"carousels": len(manifest["journeys"]), "pages": 3, "themes": len(by_theme), "output": str(OUT)}))
