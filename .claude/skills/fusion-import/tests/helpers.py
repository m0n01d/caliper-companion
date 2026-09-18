"""Shared test helpers: the golden features.json, a synthetic .ccpart.zip built on the fly (review N1: no
binary in git), tiny valid PNGs, snapshot compare/update."""

import copy
import json
import os
import struct
import sys
import zipfile
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
SKILL = HERE.parent
SCRIPTS = SKILL / "scripts"
GOLDEN_DIR = HERE / "golden"
REPO = SKILL.parent.parent.parent
GOLDEN_FEATURES = REPO / "fixtures" / "hinge_pin" / "features.json"
SCRIPT = SCRIPTS / "import_ccpart.py"

if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

import import_ccpart as _ic  # noqa: E402

_ic.PRINT_REPORT = False  # keep the test output readable; the report file is asserted instead


def golden_doc():
    return json.loads(GOLDEN_FEATURES.read_text(encoding="utf-8"))


def make_png(width, height):
    """A valid 8-bit greyscale PNG of the given size (all black), no pHYs chunk — like canvas.toBlob."""
    sig = b"\x89PNG\r\n\x1a\n"

    def chunk(ctype, body):
        return struct.pack(">I", len(body)) + ctype + body + struct.pack(">I", zlib.crc32(ctype + body) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0)
    raw = (b"\x00" + b"\x00" * width) * height
    return sig + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 1)) + chunk(b"IEND", b"")


def build_zip(dest_dir, doc=None, faces_png=True, extra_files=None, drop=()):
    """Write `<slug>.ccpart.zip` into dest_dir from `doc` (default: the golden). Returns its Path.

    faces_png=True writes a PNG at every face's `annotated` path at its pixelWidth×renderScale size, plus
    a stand-in `image` .jpg (never read by the script)."""
    doc = copy.deepcopy(doc) if doc is not None else golden_doc()
    slug = doc["part"]["slug"]
    dest_dir = Path(dest_dir)
    dest_dir.mkdir(parents=True, exist_ok=True)
    zpath = dest_dir / (slug + ".ccpart.zip")
    with zipfile.ZipFile(zpath, "w") as z:
        z.writestr("features.json", json.dumps(doc, indent=2))
        extra_files = dict(extra_files or {})
        for f in doc.get("faces", []):
            if f.get("image") and f["image"] not in drop and f["image"] not in extra_files:
                z.writestr(f["image"], b"\xff\xd8\xff\xd9")
            if faces_png and f.get("annotated") and f["annotated"] not in drop and f["annotated"] not in extra_files:
                scale = f.get("renderScale", 1)
                z.writestr(f["annotated"], make_png(int(round(f["pixelWidth"] * scale)), int(round(f["pixelHeight"] * scale))))
        for name, data in extra_files.items():
            z.writestr(name, data)
    return zpath


def snapshot(name, text):
    """Compare `text` with tests/golden/<name>; UPDATE_GOLDEN=1 rewrites it. Returns (expected, path)."""
    path = GOLDEN_DIR / name
    if os.environ.get("UPDATE_GOLDEN") == "1" or not path.exists():
        GOLDEN_DIR.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    return path.read_text(encoding="utf-8"), path
