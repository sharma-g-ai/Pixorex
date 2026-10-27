"""Build the Section 4-5 experiment image sets from the 50-image test set.

Usage:  py -I tools/preprocess.py <test_images dir> <output root>

Each set is a folder of 50 images with the same file names, ready to push to
the phone benchmark. MLKit itself is left unchanged; only the input differs.
"""
import shutil
import sys
from pathlib import Path

import cv2


def gray(img):
    return cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)


def clahe(img):
    # Local contrast boost: lifts dark text out of low light and shadow.
    return cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8)).apply(gray(img))


def denoise_clahe(img):
    # Smooth sensor noise first so CLAHE does not amplify it.
    return cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8)).apply(cv2.medianBlur(gray(img), 3))


def binarize(img):
    g = cv2.GaussianBlur(gray(img), (3, 3), 0)
    return cv2.adaptiveThreshold(g, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 31, 10)


def upscale(factor):
    return lambda img: cv2.resize(img, None, fx=factor, fy=factor, interpolation=cv2.INTER_CUBIC)


SETS = {
    "a_baseline": None,
    "b_baseline_nosym": None,
    "c_clahe": clahe,
    "d_binarize": binarize,
    "e_upscale15": upscale(1.5),
    "f_upscale2": upscale(2.0),
    "g_clahe_upscale15": lambda img: upscale(1.5)(clahe(img)),
    "h_denoise_clahe": denoise_clahe,
}


def main(src: Path, out: Path):
    images = sorted(src.glob("*.jpg"))
    for name, fn in SETS.items():
        dst = out / name
        dst.mkdir(parents=True, exist_ok=True)
        for path in images:
            if fn is None:
                shutil.copy(path, dst / path.name)
            else:
                cv2.imwrite(str(dst / path.name), fn(cv2.imread(str(path))), [cv2.IMWRITE_JPEG_QUALITY, 95])
        print(f"{name}: {len(images)} images")


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
