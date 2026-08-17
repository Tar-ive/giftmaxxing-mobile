#!/usr/bin/env python3
"""Recolor connected carousel backdrops while preserving original foreground pixels."""

from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps


ROOT = Path(__file__).parent
DOWNLOADS = Path("/Users/tarive/Downloads")
ORIGINALS = ROOT / "originals"
CARDS = ROOT / "cards"
MASKS = ROOT / "masks"

SPECS = {
    "1786131366079": {"colors": [(247, 250, 239)], "threshold": 25, "pink": (247, 215, 226)},
    "1786131367077": {"colors": [(15, 56, 80)], "threshold": 35, "pink": (218, 143, 169)},
    "1786131368068": {"colors": [(113, 51, 52), (75, 18, 20)], "threshold": 48, "pink": (218, 143, 169)},
    "1786131369078": {"colors": [(20, 18, 45), (38, 33, 64)], "threshold": 42, "pink": (208, 130, 158)},
    "1786131370085": {"colors": [(8, 8, 12), (11, 21, 32)], "threshold": 32, "pink": (201, 119, 148)},
    "1786131371068": {"colors": [(160, 60, 85), (170, 89, 106)], "threshold": 48, "pink": (229, 157, 183)},
    "1786131372069": {"colors": [(45, 38, 20), (70, 60, 35)], "threshold": 48, "pink": (204, 125, 153)},
    "1786131373074": {"colors": [(28, 72, 49), (73, 103, 80), (114, 132, 106), (183, 177, 153)], "threshold": 42, "pink": (222, 148, 174)},
    "1786131374074": {"colors": [(17, 12, 6), (68, 40, 13)], "threshold": 42, "pink": (202, 120, 150)},
    "1786131375068": {"colors": [(247, 250, 239)], "threshold": 25, "pink": (247, 215, 226)},
}


def connected_background(candidate: np.ndarray) -> np.ndarray:
    height, width = candidate.shape
    seen = np.zeros_like(candidate, dtype=bool)
    queue = deque()
    for x in range(width):
        if candidate[0, x]: queue.append((0, x))
        if candidate[height - 1, x]: queue.append((height - 1, x))
    for y in range(height):
        if candidate[y, 0]: queue.append((y, 0))
        if candidate[y, width - 1]: queue.append((y, width - 1))
    while queue:
        y, x = queue.popleft()
        if seen[y, x] or not candidate[y, x]:
            continue
        seen[y, x] = True
        if y: queue.append((y - 1, x))
        if y + 1 < height: queue.append((y + 1, x))
        if x: queue.append((y, x - 1))
        if x + 1 < width: queue.append((y, x + 1))
    return seen


def recolor(source: Path, destination: Path, mask_path: Path, spec: dict) -> None:
    image = ImageOps.exif_transpose(Image.open(source)).convert("RGB")
    rgb = np.asarray(image).astype(np.float32)
    prototypes = np.asarray(spec["colors"], dtype=np.float32)
    distance = np.sqrt(((rgb[:, :, None, :] - prototypes[None, None, :, :]) ** 2).sum(axis=3)).min(axis=2)
    mask = connected_background(distance <= spec["threshold"])
    luminance = rgb[:, :, 0] * 0.2126 + rgb[:, :, 1] * 0.7152 + rgb[:, :, 2] * 0.0722
    median = float(np.median(luminance[mask]))
    delta = (luminance - median) * 0.78
    pink = np.asarray(spec["pink"], dtype=np.float32)
    replacement = np.clip(pink[None, None, :] + delta[:, :, None], 0, 255)
    matte = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.45))
    edited = Image.composite(Image.fromarray(replacement.astype(np.uint8)), image, matte)
    edited.save(destination, quality=96, subsampling=0)
    matte.save(mask_path)


def contact_sheet(files: list[Path]) -> None:
    font = ImageFont.truetype("/System/Library/Fonts/HelveticaNeue.ttc", 22)
    columns, thumb_width, thumb_height, gap, label_height = 5, 216, 270, 16, 42
    rows = (len(files) + columns - 1) // columns
    sheet = Image.new("RGB", (gap + columns * (thumb_width + gap), gap + rows * (thumb_height + label_height + gap)), "#f4edf0")
    draw = ImageDraw.Draw(sheet)
    for index, source in enumerate(files):
        row, column = divmod(index, columns)
        x = gap + column * (thumb_width + gap)
        y = gap + row * (thumb_height + label_height + gap)
        with Image.open(source) as image:
            sheet.paste(ImageOps.fit(image.convert("RGB"), (thumb_width, thumb_height), method=Image.Resampling.LANCZOS), (x, y))
        draw.text((x, y + thumb_height + 7), f"card {index + 1:02d}", fill="#33232a", font=font)
    sheet.save(CARDS / "contact-sheet.jpg", quality=94)


CARDS.mkdir(parents=True, exist_ok=True)
MASKS.mkdir(parents=True, exist_ok=True)
outputs = []
for index, (prefix, spec) in enumerate(SPECS.items(), start=1):
    source_dir = ORIGINALS if ORIGINALS.exists() else DOWNLOADS
    source = next(source_dir.glob(f"{prefix}*.publer.com.jpg"))
    destination = CARDS / f"{index:02d}.jpg"
    recolor(source, destination, MASKS / f"{index:02d}.png", spec)
    outputs.append(destination)
contact_sheet(outputs)
print(f"Recolored {len(outputs)} cards into {CARDS}")
