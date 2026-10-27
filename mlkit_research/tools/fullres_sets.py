"""Build the full-resolution speed-test sets from phone-original photos.

Usage:  py -I tools/fullres_sets.py <fullres_originals dir> <output root>

j/k keep the camera file byte-for-byte, as the app receives it today (EXIF
orientation is not applied by BitmapFactory). l/m apply the EXIF orientation;
m also shrinks to 2400 px on the long side, the recommended pipeline.
"""
import shutil
import sys
from pathlib import Path

from PIL import Image, ImageOps


def upright(path):
    return ImageOps.exif_transpose(Image.open(path)).convert("RGB")


def shrink(img, long_side=2400):
    scale = long_side / max(img.size)
    return img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)


def main(src: Path, out: Path):
    sets = {
        "j_fullres": None,
        "k_fullres_nosym": None,
        "l_fullres_upright_nosym": upright,
        "m_upright_2400_nosym": lambda p: shrink(upright(p)),
    }
    for name, fn in sets.items():
        dst = out / name
        dst.mkdir(parents=True, exist_ok=True)
        for path in sorted(src.glob("*.jpg")):
            target = dst / path.name.replace("_fullres", f"_{name.split('_', 1)[1].replace('_nosym', '')}")
            if fn is None:
                shutil.copy(path, target)
            else:
                fn(path).save(target, quality=95)
        print(name, len(list(dst.glob("*.jpg"))))


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
