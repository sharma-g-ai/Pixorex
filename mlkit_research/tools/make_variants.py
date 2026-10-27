"""Build the 50-image MLKit test set from the 10 real delivery-note photos.

Each real page (`*_normal.jpg`) gets four simulated conditions: shadow, glare,
crumpled and low_light. Only lighting and geometry change; the printed text is
never edited, so ground_truth_*.csv stays valid for every variant.

Usage:  py -I tools/make_variants.py <test_images dir>
"""
import csv
import sys
import zlib
from pathlib import Path

import cv2
import numpy as np

CONDITIONS = ("shadow", "glare", "crumpled", "low_light")


def _rng(name: str, condition: str) -> np.random.Generator:
    # Stable seed per image + condition so reruns produce identical files.
    return np.random.default_rng(zlib.crc32(f"{name}:{condition}".encode()))


def shadow(img, rng):
    h, w = img.shape[:2]
    mask = np.zeros((h, w), np.float32)
    # Hand-and-phone shaped blob: an ellipse plus an arm reaching to the edge.
    cx, cy = int(w * rng.uniform(0.35, 0.65)), int(h * rng.uniform(0.3, 0.6))
    ax, ay = int(w * rng.uniform(0.12, 0.2)), int(h * rng.uniform(0.15, 0.22))
    cv2.ellipse(mask, (cx, cy), (ax, ay), rng.uniform(-30, 30), 0, 360, 1.0, -1)
    edge = (int(w * rng.uniform(0.6, 1.0)), h)
    cv2.line(mask, (cx, cy), edge, 1.0, int(w * 0.12))
    mask = cv2.GaussianBlur(mask, (0, 0), w * 0.025)
    strength = rng.uniform(0.45, 0.6)
    shade = 1.0 - strength * mask
    return np.clip(img * shade[..., None], 0, 255)


def glare(img, rng):
    h, w = img.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    # Put the hot spot over the item table, where it hurts OCR the most.
    cx, cy = w * rng.uniform(0.3, 0.7), h * rng.uniform(0.45, 0.7)
    sx, sy = w * rng.uniform(0.12, 0.2), h * rng.uniform(0.07, 0.12)
    spot = np.exp(-(((xx - cx) / sx) ** 2 + ((yy - cy) / sy) ** 2))
    alpha = (rng.uniform(0.75, 0.9) * spot)[..., None]
    out = img * (1 - alpha) + 255 * alpha
    # Faint wide sheen over the whole page, like an overhead tube light.
    sheen = np.exp(-(((xx - cx) / (sx * 3)) ** 2 + ((yy - cy) / (sy * 4)) ** 2))
    out = out + 25 * sheen[..., None]
    return np.clip(out, 0, 255)


def crumpled(img, rng):
    h, w = img.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    height = np.zeros((h, w), np.float32)
    for _ in range(rng.integers(4, 7)):
        # Each fold is a ridge along a random line across the page.
        ang = rng.uniform(0, np.pi)
        nx, ny = np.cos(ang), np.sin(ang)
        off = rng.uniform(0.2, 0.8) * (abs(nx) * w + abs(ny) * h)
        dist = xx * nx + yy * ny - off
        height += rng.choice([-1, 1]) * np.exp(-np.abs(dist) / rng.uniform(25, 60))
    height += cv2.GaussianBlur(rng.normal(0, 1, (h, w)).astype(np.float32), (0, 0), 40) * 3
    # Round the ridges so folds bend text instead of tearing or duplicating it.
    height = cv2.GaussianBlur(height, (0, 0), 10)
    gy, gx = np.gradient(height)
    light = 1.0 + 8.0 * (gx * 0.6 + gy * 0.8)
    light = np.clip(light, 0.65, 1.15)
    # Displace pixels a little along the folds so text lines bend.
    amp = 2.5
    map_x = (xx + amp * gx * 40).astype(np.float32)
    map_y = (yy + amp * gy * 40).astype(np.float32)
    warped = cv2.remap(img.astype(np.float32), map_x, map_y, cv2.INTER_LINEAR,
                       borderMode=cv2.BORDER_REPLICATE)
    return np.clip(warped * light[..., None], 0, 255)


def low_light(img, rng):
    dark = 255 * (img / 255.0) ** rng.uniform(1.8, 2.2) * rng.uniform(0.4, 0.5)
    dark = dark * np.array([0.85, 0.95, 1.08])  # warm indoor bulb (BGR)
    noise = rng.normal(0, rng.uniform(7, 10), dark.shape)
    dark = cv2.GaussianBlur(np.clip(dark + noise, 0, 255).astype(np.float32), (3, 3), 0.8)
    return np.clip(dark, 0, 255)


EFFECTS = {"shadow": shadow, "glare": glare, "crumpled": crumpled, "low_light": low_light}


def main(folder: Path) -> None:
    bases = sorted(folder.glob("*_normal.jpg"))
    if len(bases) != 10:
        sys.exit(f"expected 10 *_normal.jpg files in {folder}, found {len(bases)}")
    rows = []
    for base in bases:
        img = cv2.imread(str(base)).astype(np.float32)
        stem = base.stem[: -len("_normal")]
        dn_tag, dn, page = stem.split("_")
        rows.append([base.name, dn, page[1:], "normal", "real photo"])
        for cond in CONDITIONS:
            out = EFFECTS[cond](img, _rng(base.name, cond)).astype(np.uint8)
            name = f"{stem}_{cond}.jpg"
            # Low light photos come out of phones more compressed.
            quality = 75 if cond == "low_light" else 90
            cv2.imwrite(str(folder / name), out, [cv2.IMWRITE_JPEG_QUALITY, quality])
            rows.append([name, dn, page[1:], cond, f"simulated from {base.name}"])
    with open(folder.parent / "test_set_manifest.csv", "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["image_file", "dn_number", "page", "condition", "source"])
        writer.writerows(rows)
    print(f"wrote {len(rows)} images")


if __name__ == "__main__":
    main(Path(sys.argv[1]))
