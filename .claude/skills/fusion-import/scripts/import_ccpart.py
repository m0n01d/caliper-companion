"""import_ccpart.py — Caliper Companion → Fusion 360 import (SPEC.md §7, docs/fusion/IMPORT-SKILL-SPEC.md).

One self-contained file, three layers:

  planner   plan_import(path) — pure Python, no `adsk`: a `<slug>.ccpart.zip`, an unzipped folder or a
            bare features.json → a plan (parameters, sketches, canvases, warnings) or a refusal.
  executor  run_import(args) / execute(plan, design, args) — Fusion API (`adsk`), only importable inside
            Fusion. `mode="inspect"` is read-only; `mode="execute"` mutates the active design.
  cli       --dry-run / --extract / --emit / --inspect / --execute, plain python3 on the shell side.

How it runs through the Fusion MCP (spec §1b): the skill unzips on the shell side into
~/.caliper-companion/imports/<slug>/ (writing a pHYs chunk into each *_dimensioned.png copy so the canvas
comes in 100 mm wide), then sends this file's text followed by one trailing line

    __ccpart = run_import({'mode': 'inspect', 'dir': '/Users/…/imports/<slug>', …})

twice: first `inspect`, then — after the user confirmed the plan — `execute`. The report is returned,
printed as JSON and written to `<dir>/import-report.json` (the channel the skill reads). No `ui.messageBox`
anywhere on the MCP path; every error is a report entry.

Without Claude (Fusion → Utilities → Scripts and Add-Ins → Run): `run(context)` finds neither `__ccpart`
nor a `CCPART_ARGS` global and takes the standalone path — a file dialog for the `.ccpart.zip` (or a
`features.json`), the same extraction + pHYs rewrite done inside Fusion's Python, the plan shown in an
OK/Cancel message box, execute on OK, a summary message box, and the same `import-report.json`. Message
boxes are fine here because nothing is holding an MCP call open.

Idempotent by ownership, never by name alone. Everything the import creates is tagged: a parameter's
comment ends `· ccpart:<slug>`; sketches and canvases carry the attribute group `caliper-companion`
(`ccpart = <slug>`, `face = <label>`). On re-import:
  * parameter exists and is ours  → expression, unit and comment updated (previous values reported)
  * sketch exists and is ours     → kept, untouched (the user's geometry lives there)
  * canvas exists and is ours     → re-added from the new PNG, carrying the old transform when the pixel
                                    size is unchanged; the old canvas is deleted only after the new exists
  * name exists and is NOT ours   → collision: `inspect` lists it, `execute` refuses unless force=True

Rollback (cookbook trap 2): every created entity is appended to a list; on any exception `deleteMe()` runs
in reverse creation order and the report names anything that would not delete. Updated parameters are not
rolled back — their previous expressions are in the report for a manual restore.

Units (cookbook trap 1): lengths only ever reach Fusion as expression strings ("42.18 mm", "1.375 in").
"""

import json
import os
import re
import struct
import sys
import traceback
import zipfile
import zlib
from pathlib import Path

SCHEMA = "caliper-companion/features/1"
ATTR_GROUP = "caliper-companion"
CANVAS_WIDTH_MM = 100.0
CANVAS_OPACITY = 60  # int 0–100 (review B2)
DEFER_COMPUTE_ABOVE_FACES = 6
WARN_ABOVE_FACES = 8
DEFAULT_IMPORTS_DIR = "~/.caliper-companion/imports"
REPORT_FILE = "import-report.json"
PRINT_REPORT = True  # run_import also prints the report as one JSON line (tests switch this off)

NAME_RE = re.compile(r"^[a-z][a-z0-9_]{0,31}$")
SLUG_RE = re.compile(r"^[a-z][a-z0-9_]{0,39}$")
MODEL_PARAM_RE = re.compile(r"^d\d+$")  # Fusion's auto-named model parameters (review S5)
# SPEC §6.2 reserved list (Fusion math functions) + unit names Fusion rejects (review S5).
RESERVED = {
    "pi", "e", "sin", "cos", "tan", "sqrt", "abs", "floor", "ceil", "round", "min", "max", "log", "ln", "exp",
}
RESERVED_UNITS = {"mm", "cm", "m", "in", "ft", "deg", "rad"}

FEATURE_KINDS = ("length", "diameter", "depth")
KIND_ORDER = ("top", "side", "end", "detail")
KIND_PLANE = {
    "top": "xYConstructionPlane",
    "side": "xZConstructionPlane",
    "end": "yZConstructionPlane",
    "detail": "xYConstructionPlane",
}
UNITS = ("mm", "in")

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


class RefuseImport(Exception):
    """Raised by the planner (and the executor's pre-checks) before anything is touched."""

    def __init__(self, reasons):
        self.reasons = [reasons] if isinstance(reasons, str) else list(reasons)
        super().__init__("; ".join(self.reasons))


# ---------------------------------------------------------------------------------------------------------------
# Planner (pure)
# ---------------------------------------------------------------------------------------------------------------


def fmt_number(v):
    """4 dp, trailing zeros stripped, never exponent notation (review S4). 42.18 → "42.18", 2.0 → "2"."""
    s = "{:.4f}".format(float(v)).rstrip("0").rstrip(".")
    return "0" if s in ("", "-0") else s


def _is_finite_number(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and v == v and v not in (float("inf"), float("-inf"))


class Source(object):
    """Where features.json and the bundle files come from: zip, folder, or a bare features.json."""

    def __init__(self, kind, root, names):
        self.kind = kind  # "zip" | "dir" | "json"
        self.root = root  # Path of the zip / folder / json file
        self._names = names  # set of bundle-relative paths, or None for a bare json

    def has(self, rel):
        return self._names is not None and rel in self._names

    def read(self, rel):
        if self.kind == "zip":
            with zipfile.ZipFile(self.root) as z:
                return z.read(rel)
        if self.kind == "dir":
            return (self.root / rel).read_bytes()
        raise FileNotFoundError(rel)


def _safe_rel(rel):
    """A bundle-relative path that cannot escape: no absolute, no drive, no '..' segment."""
    if not isinstance(rel, str) or rel == "":
        return False
    p = rel.replace("\\", "/")
    if p.startswith("/") or re.match(r"^[A-Za-z]:", p):
        return False
    return all(seg not in ("", ".", "..") for seg in p.split("/"))


def load_source(path):
    """Open a .ccpart.zip, an unzipped folder, or a bare features.json → (features dict, Source)."""
    p = Path(path).expanduser()
    if not p.exists():
        raise RefuseImport("not found: {}".format(p))
    if p.is_dir():
        fj = p / "features.json"
        if not fj.exists():
            raise RefuseImport("no features.json in folder {}".format(p))
        names = set()
        for f in p.rglob("*"):
            if f.is_file():
                names.add(f.relative_to(p).as_posix())
        doc = _parse_json(fj.read_bytes(), str(fj))
        return doc, Source("dir", p, names)
    if zipfile.is_zipfile(str(p)):
        with zipfile.ZipFile(p) as z:
            names = set(z.namelist())
            if "features.json" not in names:
                raise RefuseImport("no features.json at the root of {}".format(p.name))
            for n in names:
                if not _safe_rel(n) and not n.endswith("/"):
                    raise RefuseImport("unsafe path inside zip: {!r}".format(n))
            doc = _parse_json(z.read("features.json"), "{}!features.json".format(p.name))
        return doc, Source("zip", p, names)
    doc = _parse_json(p.read_bytes(), str(p))
    return doc, Source("json", p, None)


def _parse_json(data, label):
    try:
        doc = json.loads(data.decode("utf-8"))
    except Exception as exc:  # noqa: BLE001 — surface as a refusal
        raise RefuseImport("{}: not valid JSON ({})".format(label, exc))
    if not isinstance(doc, dict):
        raise RefuseImport("{}: top level is not an object".format(label))
    return doc


def _validate_name(name, what, errors):
    if not isinstance(name, str) or not NAME_RE.match(name):
        errors.append("{} {!r} fails the name rule ^[a-z][a-z0-9_]{{0,31}}$".format(what, name))
        return False
    if name in RESERVED or name in RESERVED_UNITS or MODEL_PARAM_RE.match(name):
        errors.append("{} {!r} is reserved by Fusion".format(what, name))
        return False
    return True


def plan_from_document(doc, source=None):
    """features.json dict (+ optional Source for file checks) → plan dict. Raises RefuseImport."""
    errors = []
    warnings = []

    schema = doc.get("schema")
    if schema != SCHEMA:
        raise RefuseImport("unknown schema {!r} (expected {!r})".format(schema, SCHEMA))

    part = doc.get("part")
    if not isinstance(part, dict):
        raise RefuseImport("missing part object")
    slug = part.get("slug")
    if not isinstance(slug, str) or not SLUG_RE.match(slug):
        raise RefuseImport("part.slug {!r} fails ^[a-z][a-z0-9_]{{0,39}}$".format(slug))
    units = part.get("units")
    if units not in UNITS:
        raise RefuseImport("part.units {!r} is not one of {}".format(units, list(UNITS)))
    part_name = part.get("name") if isinstance(part.get("name"), str) else slug
    part_path = part.get("path") if isinstance(part.get("path"), str) else ""  # A10, "" when absent (review N3)

    faces = doc.get("faces")
    if not isinstance(faces, list) or len(faces) == 0:
        raise RefuseImport("faces is empty: nothing to import")
    features = doc.get("features")
    if features is None:
        features = []
    if not isinstance(features, list):
        raise RefuseImport("features is not a list")

    # ---- faces → sketches -----------------------------------------------------------------------------------
    face_by_id = {}
    labels_seen = set()
    face_rows = []
    for i, f in enumerate(faces):
        if not isinstance(f, dict):
            errors.append("faces[{}] is not an object".format(i))
            continue
        fid = f.get("id")
        kind = f.get("kind")
        label = f.get("label", kind)  # pre-A7 exports: label == kind
        if not isinstance(fid, str) or fid == "":
            errors.append("faces[{}] has no id".format(i))
            continue
        if fid in face_by_id:
            errors.append("duplicate face id {!r}".format(fid))
            continue
        if kind not in KIND_PLANE:
            errors.append("face {!r} has unknown kind {!r} (expected one of {})".format(label, kind, list(KIND_ORDER)))
            continue
        if not _validate_name(label, "face label", errors):
            continue
        if label in labels_seen:
            errors.append("duplicate face label {!r}".format(label))
            continue
        labels_seen.add(label)
        face_by_id[fid] = label
        annotated = f.get("annotated")
        canvas_file = None
        png_size = None
        if not isinstance(annotated, str) or annotated == "":
            warnings.append("face {!r}: no annotated file in features.json; canvas skipped".format(label))
        elif not _safe_rel(annotated):
            errors.append("face {!r}: unsafe annotated path {!r}".format(label, annotated))
        elif source is None or source.kind == "json":
            warnings.append("face {!r}: bare features.json, no bundle files; canvas skipped".format(label))
        elif not source.has(annotated):
            warnings.append("face {!r}: annotated file {!r} missing from the bundle; canvas skipped".format(label, annotated))
        else:
            canvas_file = annotated
            try:
                png_size = png_dimensions_bytes(source.read(annotated))
            except Exception as exc:  # noqa: BLE001
                errors.append("face {!r}: {!r} is not a PNG ({})".format(label, annotated, exc))
                continue
            expect_w = f.get("pixelWidth")
            expect_h = f.get("pixelHeight")
            scale = f.get("renderScale", 1)
            if _is_finite_number(expect_w) and _is_finite_number(expect_h) and _is_finite_number(scale):
                ew = int(round(expect_w * scale))
                eh = int(round(expect_h * scale))
                if (ew, eh) != png_size:
                    warnings.append(
                        "face {!r}: PNG is {}x{} px but features.json says {}x{} (pixelWidth × renderScale); "
                        "using the PNG".format(label, png_size[0], png_size[1], ew, eh)
                    )
        face_rows.append(
            {
                "name": label,
                "kind": kind,
                "plane": KIND_PLANE[kind],
                "canvas_file": canvas_file,
                "canvas_name": label + "_photo",
                "png_width": png_size[0] if png_size else None,
                "png_height": png_size[1] if png_size else None,
                "face_id": fid,
            }
        )
    face_rows.sort(key=lambda r: (KIND_ORDER.index(r["kind"]), r["name"]))

    # ---- features → parameters --------------------------------------------------------------------------------
    params = []
    names_seen = {}
    flagged_names = []
    for i, ft in enumerate(features):
        if not isinstance(ft, dict):
            errors.append("features[{}] is not an object".format(i))
            continue
        name = ft.get("name")
        if not _validate_name(name, "feature name", errors):
            continue
        kind = ft.get("kind")
        if kind not in FEATURE_KINDS:
            errors.append("feature {!r} has unknown kind {!r} (expected one of {})".format(name, kind, list(FEATURE_KINDS)))
            continue
        if name in names_seen:
            if names_seen[name] != kind:
                errors.append("kind conflict: feature {!r} appears as {} and {}".format(name, names_seen[name], kind))
            else:
                errors.append("duplicate feature {!r}".format(name))
            continue
        names_seen[name] = kind
        value = ft.get("value")
        if not _is_finite_number(value) or value <= 0:
            errors.append("feature {!r}: value {!r} must be a finite number > 0".format(name, value))
            continue
        if fmt_number(value) == "0":
            errors.append("feature {!r}: value {!r} rounds to 0 at 4 dp".format(name, value))
            continue
        tol = ft.get("tolerance", 0)
        if not _is_finite_number(tol) or tol < 0:
            errors.append("feature {!r}: tolerance {!r} must be a finite number >= 0".format(name, tol))
            continue
        spread = ft.get("spread", 0)
        if not _is_finite_number(spread) or spread < 0:
            errors.append("feature {!r}: spread {!r} must be a finite number >= 0".format(name, spread))
            continue
        face_ids = ft.get("faceIds") or []
        if not isinstance(face_ids, list):
            errors.append("feature {!r}: faceIds is not a list".format(name))
            continue
        labels = []
        bad = False
        for fid in face_ids:
            if fid not in face_by_id:
                errors.append("feature {!r}: faceIds entry {!r} is not in faces[]".format(name, fid))
                bad = True
            else:
                labels.append(face_by_id[fid])
        if bad:
            continue
        flagged = bool(ft.get("flagged", False))
        comment = "{} ±{} {} · faces {} · ccpart:{}".format(kind, fmt_number(tol), units, ", ".join(labels) or "-", slug)
        if flagged:
            comment = "FLAGGED spread {} > ±{} · ".format(fmt_number(spread), fmt_number(tol)) + comment
            flagged_names.append(name)
            warnings.append(
                "feature {!r} is FLAGGED: spread {} > tolerance ±{} {} — parameter written with the mean value; "
                "check the caliper readings".format(name, fmt_number(spread), fmt_number(tol), units)
            )
        params.append(
            {
                "name": name,
                "expression": "{} {}".format(fmt_number(value), units),
                "unit": units,
                "comment": comment,
                "kind": kind,
                "flagged": flagged,
            }
        )

    if errors:
        raise RefuseImport(errors)

    if not params:
        warnings.append("no features in the export: photos-only import (sketches and canvases, no parameters)")
    if len(face_rows) > WARN_ABOVE_FACES:
        warnings.append(
            "{} faces: the execute call may take a while (Fusion's UI freezes until it finishes)".format(len(face_rows))
        )

    return {
        "schema": SCHEMA,
        "slug": slug,
        "part_name": part_name,
        "part_path": part_path,
        "units": units,
        "exported_at": doc.get("exportedAt") if isinstance(doc.get("exportedAt"), str) else "",
        "group_name": "{} import".format(slug),
        "canvas_width_mm": CANVAS_WIDTH_MM,
        "canvas_opacity": CANVAS_OPACITY,
        "parameters": params,
        "sketches": face_rows,
        "flagged": flagged_names,
        "warnings": warnings,
    }


def plan_import(path):
    """Path (zip | folder | features.json) → plan dict. Raises RefuseImport."""
    doc, source = load_source(path)
    return plan_from_document(doc, source)


def plan_summary(plan):
    """Human lines for the confirmation prompt."""
    lines = [
        "{} ({}) — {} parameters, {} sketches, {} canvases".format(
            plan["part_name"],
            plan["slug"],
            len(plan["parameters"]),
            len(plan["sketches"]),
            sum(1 for s in plan["sketches"] if s["canvas_file"]),
        )
    ]
    for p in plan["parameters"]:
        lines.append("  param   {:<32} {:<12} {}".format(p["name"], p["expression"], p["comment"]))
    for s in plan["sketches"]:
        lines.append(
            "  sketch  {:<32} {:<22} canvas {}".format(
                s["name"], s["plane"], (s["canvas_name"] + " ← " + s["canvas_file"]) if s["canvas_file"] else "(none)"
            )
        )
    for w in plan["warnings"]:
        lines.append("  warning " + w)
    return "\n".join(lines)


# ---------------------------------------------------------------------------------------------------------------
# PNG helpers (stdlib): IHDR size, pHYs chunk (review B2, route (a))
# ---------------------------------------------------------------------------------------------------------------


def png_dimensions_bytes(data):
    """(width, height) from a PNG's IHDR. Raises ValueError for a non-PNG."""
    if len(data) < 24 or data[:8] != PNG_SIGNATURE or data[12:16] != b"IHDR":
        raise ValueError("not a PNG")
    return struct.unpack(">II", data[16:24])


def png_dimensions(path):
    with open(str(path), "rb") as fh:
        return png_dimensions_bytes(fh.read(24))


def png_chunks(data):
    """Yield (type, data) for every chunk, verifying CRCs."""
    if data[:8] != PNG_SIGNATURE:
        raise ValueError("not a PNG")
    pos = 8
    while pos + 8 <= len(data):
        (length,) = struct.unpack(">I", data[pos : pos + 4])
        ctype = data[pos + 4 : pos + 8]
        body = data[pos + 8 : pos + 8 + length]
        (crc,) = struct.unpack(">I", data[pos + 8 + length : pos + 12 + length])
        if zlib.crc32(ctype + body) & 0xFFFFFFFF != crc:
            raise ValueError("bad CRC on {!r} chunk".format(ctype))
        yield ctype, body
        pos += 12 + length
        if ctype == b"IEND":
            break


def _chunk(ctype, body):
    return struct.pack(">I", len(body)) + ctype + body + struct.pack(">I", zlib.crc32(ctype + body) & 0xFFFFFFFF)


def phys_pixels_per_metre(width_px, width_mm=CANVAS_WIDTH_MM):
    """pixels-per-metre so that `width_px` renders `width_mm` wide: 1600 px at 100 mm → 16000."""
    return int(round(width_px * 1000.0 / float(width_mm)))


def write_phys(src, dst=None, width_mm=CANVAS_WIDTH_MM):
    """Rewrite a PNG with a pHYs chunk (metre units) right after IHDR, replacing any existing pHYs.

    Returns the pixels-per-metre written. `dst` defaults to in-place."""
    src = Path(src)
    dst = Path(dst) if dst is not None else src
    data = src.read_bytes()
    chunks = list(png_chunks(data))
    if not chunks or chunks[0][0] != b"IHDR":
        raise ValueError("{}: IHDR is not the first chunk".format(src))
    width, _height = struct.unpack(">II", chunks[0][1][:8])
    ppm = phys_pixels_per_metre(width, width_mm)
    phys = struct.pack(">IIB", ppm, ppm, 1)
    out = [PNG_SIGNATURE, _chunk(b"IHDR", chunks[0][1]), _chunk(b"pHYs", phys)]
    for ctype, body in chunks[1:]:
        if ctype == b"pHYs":
            continue
        out.append(_chunk(ctype, body))
    dst.write_bytes(b"".join(out))
    return ppm


def read_phys(data):
    """(ppm_x, ppm_y, unit) of the pHYs chunk, or None."""
    for ctype, body in png_chunks(data):
        if ctype == b"pHYs":
            return struct.unpack(">IIB", body)
    return None


# ---------------------------------------------------------------------------------------------------------------
# Shell side: extract + emit the MCP code
# ---------------------------------------------------------------------------------------------------------------


def extract_bundle(path, to_dir=DEFAULT_IMPORTS_DIR):
    """Stage a `<slug>.ccpart.zip` (unzipped), an unzipped folder or a bare features.json (copied) into
    `<to_dir>/<slug>/`, write pHYs into every planned canvas PNG copy, drop any stale report.
    Pure stdlib, so it runs on the shell side and inside Fusion's Python alike. Returns (plan, dir)."""
    path = Path(path).expanduser()
    doc, source = load_source(path)
    plan = plan_from_document(doc, source)
    dest = Path(to_dir).expanduser() / plan["slug"]
    if source.kind == "dir" and dest.resolve() == source.root.resolve():
        raise RefuseImport("{} is already the staging folder; use --dry-run or pass it as dir".format(dest))
    dest.mkdir(parents=True, exist_ok=True)
    if source.kind == "zip":
        with zipfile.ZipFile(path) as z:
            for info in z.infolist():
                if info.is_dir():
                    continue
                if not _safe_rel(info.filename):
                    raise RefuseImport("unsafe path inside zip: {!r}".format(info.filename))
                target = dest / info.filename
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(z.read(info))
    else:
        (dest / "features.json").write_bytes(path.read_bytes() if source.kind == "json" else (source.root / "features.json").read_bytes())
        for s in plan["sketches"]:
            if s["canvas_file"]:
                target = dest / s["canvas_file"]
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(source.read(s["canvas_file"]))
    stale = dest / REPORT_FILE
    if stale.exists():
        stale.unlink()
    for s in plan["sketches"]:
        if s["canvas_file"]:
            write_phys(dest / s["canvas_file"], width_mm=plan["canvas_width_mm"])
    return plan, dest


def default_args(mode, directory, new_document=False, group=True, force=False, strict=False):
    return {
        "mode": mode,
        "dir": str(directory),
        "new_document": bool(new_document),
        "group": bool(group),
        "force": bool(force),
        "strict": bool(strict),
    }


def mcp_code(args, script_path=None):
    """The exact string to send to the Fusion MCP's script tool: this file's text + one trailing line.

    `repr(args)` is a Python literal (json.dumps is not: true/null), so a path with spaces, quotes or
    non-ASCII survives verbatim — never build this with an f-string."""
    src = Path(script_path) if script_path else Path(__file__)
    text = src.read_text(encoding="utf-8")
    if not text.endswith("\n"):
        text += "\n"
    return text + "\n__ccpart = run_import(" + repr(dict(args)) + ")\n"


# ---------------------------------------------------------------------------------------------------------------
# Executor (Fusion API). Everything below only runs inside Fusion (or against fake_adsk in tests).
# ---------------------------------------------------------------------------------------------------------------


def _adsk():
    try:
        import adsk.core  # noqa: F401
        import adsk.fusion  # noqa: F401
    except ImportError:
        return None
    return adsk


def _attr_value(entity, name):
    try:
        a = entity.attributes.itemByName(ATTR_GROUP, name)
    except Exception:  # noqa: BLE001 — an entity type without attributes
        return None
    return a.value if a is not None else None


def _tag(entity, slug, label, extra=None):
    entity.attributes.add(ATTR_GROUP, "ccpart", slug)
    entity.attributes.add(ATTR_GROUP, "face", label)
    for k, v in (extra or {}).items():
        entity.attributes.add(ATTR_GROUP, k, v)


def _by_name(collection, name):
    """`itemByName` when the collection has it, else a linear scan (Canvases: verify V5)."""
    fn = getattr(collection, "itemByName", None)
    if fn is not None:
        return fn(name)
    for i in range(collection.count):
        item = collection.item(i)
        if item.name == name:
            return item
    return None


def _owns_parameter(param, slug):
    return "ccpart:{}".format(slug) in (param.comment or "")


def _safe(getter, default=None):
    try:
        return getter()
    except Exception:  # noqa: BLE001
        return default


def inspect_design(adsk, design, plan):
    """Read-only look at the design against the plan: what exists, who owns it, what would happen."""
    slug = plan["slug"]
    comp = design.activeComponent
    root = design.rootComponent
    parametric = design.designType == adsk.fusion.DesignTypes.ParametricDesignType
    timeline = design.timeline if parametric else None
    tl_count = _safe(lambda: timeline.count, 0) if timeline is not None else 0
    tl_marker = _safe(lambda: timeline.markerPosition, tl_count) if timeline is not None else 0
    occurrences = _safe(lambda: root.occurrences.count, 0)
    user_params = _safe(lambda: design.userParameters.count, 0)

    touched = []
    collisions = []
    for p in plan["parameters"]:
        existing = design.userParameters.itemByName(p["name"])
        if existing is None:
            continue
        owned = _owns_parameter(existing, slug)
        touched.append(
            {
                "kind": "parameter",
                "name": p["name"],
                "owned": owned,
                "action": "update" if owned else "collision",
                "existing": {"expression": existing.expression, "unit": existing.unit, "comment": existing.comment},
            }
        )
        if not owned:
            collisions.append("parameter " + p["name"])
    for s in plan["sketches"]:
        sk = _by_name(comp.sketches, s["name"])
        if sk is not None:
            owned = _attr_value(sk, "ccpart") == slug
            touched.append({"kind": "sketch", "name": s["name"], "owned": owned, "action": "keep" if owned else "collision"})
            if not owned:
                collisions.append("sketch " + s["name"])
        if s["canvas_file"]:
            cv = _by_name(comp.canvases, s["canvas_name"])
            if cv is not None:
                owned = _attr_value(cv, "ccpart") == slug
                touched.append(
                    {
                        "kind": "canvas",
                        "name": s["canvas_name"],
                        "owned": owned,
                        "action": "refresh" if owned else "collision",
                        "existing_pixels": _attr_value(cv, "pixels"),
                    }
                )
                if not owned:
                    collisions.append("canvas " + s["canvas_name"])

    return {
        "document": _safe(lambda: design.parentDocument.name, "?"),
        "design_type": "parametric" if parametric else "direct",
        "component": _safe(lambda: comp.name, "?"),
        "component_is_root": _safe(lambda: comp == root, True),
        "length_unit": _safe(lambda: design.fusionUnitsManager.defaultLengthUnits, "?"),
        "timeline_count": tl_count,
        "timeline_marker": tl_marker,
        "timeline_rolled_back": bool(parametric and tl_marker != tl_count),
        "user_parameters": user_params,
        "occurrences": occurrences,
        "has_user_work": bool(tl_count > 0 or user_params > 0 or occurrences > 0),
        "touched": touched,
        "collisions": collisions,
    }


def execute(adsk, plan, design, args, directory, inspect=None):
    """Mutate `design` per `plan`. Returns the result dict (never raises; failures are in the dict)."""
    slug = plan["slug"]
    directory = Path(directory)
    force = bool(args.get("force", False))
    want_group = bool(args.get("group", True))
    result = {
        "component": "?",
        "component_is_root": True,
        "created": [],
        "updated": [],
        "kept": [],
        "refreshed": [],
        "skipped": [],
        "previous": {},
        "carried_transforms": [],
        "group": None,
        "warnings": list(plan["warnings"]),
        "canvas_note": (
            "Canvases are uncalibrated: nominal {:g} mm wide via a pHYs chunk in the extracted PNG copy, centred "
            "on the plane origin, opacity {} (SPEC §1: the photo is a sketch, not a measurement). Calibrate in "
            "Fusion (Canvas → Calibrate) if you want them to scale; a re-import carries that calibration over."
        ).format(plan["canvas_width_mm"], plan["canvas_opacity"]),
        "ok": True,
    }
    created = []  # (kind, name, entity) — rollback list, reverse order on failure (cookbook trap 2)
    comp = design.activeComponent
    root = design.rootComponent
    is_root = _safe(lambda: comp == root, True)
    result["component"] = _safe(lambda: comp.name, "?")
    result["component_is_root"] = is_root
    if is_root:
        # Single-component design (or the root activated): work in rootComponent, as the cookbook says to.
        result["warnings"].append("target component is the root component")
    parametric = design.designType == adsk.fusion.DesignTypes.ParametricDesignType
    if not parametric:
        result["warnings"].append("Direct-modeling design: no timeline group")
    defer = len(plan["sketches"]) > DEFER_COMPUTE_ABOVE_FACES
    try:
        if defer:
            design.isComputeDeferred = True
        # ---- parameters: upsert by name, ownership-checked -------------------------------------------------
        for p in plan["parameters"]:
            existing = design.userParameters.itemByName(p["name"])
            if existing is not None:
                if not _owns_parameter(existing, slug) and not force:
                    raise RuntimeError("parameter {!r} is not ours (comment {!r})".format(p["name"], existing.comment))
                result["previous"][p["name"]] = {
                    "expression": existing.expression,
                    "unit": existing.unit,
                    "comment": existing.comment,
                }
                existing.expression = p["expression"]
                existing.unit = p["unit"]
                existing.comment = p["comment"]
                result["updated"].append("parameter " + p["name"])
            else:
                vi = adsk.core.ValueInput.createByString(p["expression"])
                new = design.userParameters.add(p["name"], vi, p["unit"], p["comment"])
                if new is None:
                    raise RuntimeError("userParameters.add returned None for {!r}".format(p["name"]))
                created.append(("parameter", p["name"], new))
                result["created"].append("parameter " + p["name"])
        # ---- sketches (kept if present) + canvases (refreshed) -------------------------------------------------
        for s in plan["sketches"]:
            plane = getattr(comp, s["plane"])
            sk = _by_name(comp.sketches, s["name"])
            if sk is not None:
                if _attr_value(sk, "ccpart") != slug and not force:
                    raise RuntimeError("sketch {!r} is not ours".format(s["name"]))
                result["kept"].append("sketch " + s["name"])
            else:
                sk = comp.sketches.add(plane)
                if sk is None:
                    raise RuntimeError("sketches.add returned None for {!r}".format(s["name"]))
                created.append(("sketch", s["name"], sk))
                sk.name = s["name"]
                _tag(sk, slug, s["name"])
                result["created"].append("sketch " + s["name"])
            if not s["canvas_file"]:
                result["skipped"].append("canvas " + s["canvas_name"])
                continue
            png_path = directory / s["canvas_file"]
            if not png_path.exists():
                result["warnings"].append("canvas {}: {} missing on disk; skipped".format(s["canvas_name"], png_path))
                result["skipped"].append("canvas " + s["canvas_name"])
                continue
            pixels = "{}x{}".format(*png_dimensions(png_path))
            old = _by_name(comp.canvases, s["canvas_name"])
            transform = None
            if old is not None:
                if _attr_value(old, "ccpart") != slug and not force:
                    raise RuntimeError("canvas {!r} is not ours".format(s["canvas_name"]))
                if _attr_value(old, "pixels") == pixels:
                    transform = old.transform.copy()
                else:
                    result["warnings"].append(
                        "canvas {}: pixel size changed ({} → {}); calibration not carried".format(
                            s["canvas_name"], _attr_value(old, "pixels"), pixels
                        )
                    )
            ci = comp.canvases.createInput(str(png_path), plane)
            ci.opacity = plan["canvas_opacity"]
            if transform is not None:
                ci.transform = transform
            cv = comp.canvases.add(ci)
            if cv is None:
                raise RuntimeError("canvases.add returned None for {!r}".format(s["canvas_name"]))
            created.append(("canvas", s["canvas_name"], cv))
            if old is not None:
                # New canvas exists; only now drop the old one, so a failed refresh keeps the old canvas.
                if not old.deleteMe():
                    raise RuntimeError("could not delete the previous canvas {!r}".format(s["canvas_name"]))
                result["refreshed"].append("canvas " + s["canvas_name"])
                if transform is not None:
                    result["carried_transforms"].append(s["canvas_name"])
            else:
                result["created"].append("canvas " + s["canvas_name"])
            cv.name = s["canvas_name"]
            _tag(cv, slug, s["name"], {"pixels": pixels})
        # ---- timeline group around what THIS run created (kept sketches stay where they are) -------------------
        if parametric and want_group:
            indices = []
            for kind, _name, entity in created:
                if kind in ("sketch", "canvas"):
                    to = entity.timelineObject
                    if to is not None:
                        indices.append(to.index)
            if indices:
                g = design.timeline.timelineGroups.add(min(indices), max(indices))
                g.name = plan["group_name"]
                result["group"] = plan["group_name"]
    except Exception:  # noqa: BLE001 — rollback, then report
        result["ok"] = False
        result["error"] = traceback.format_exc()
        deleted = []
        failed = []
        for kind, name, entity in reversed(created):
            try:
                ok = entity.deleteMe()
            except Exception:  # noqa: BLE001
                ok = False
            (deleted if ok else failed).append("{} {}".format(kind, name))
        result["rollback"] = {"deleted": deleted, "failed": failed}
        result["created"] = []
        result["refreshed"] = []
        result["kept"] = []
    finally:
        if defer:
            design.isComputeDeferred = False
    return result


def _write_report(directory, report):
    try:
        Path(directory).mkdir(parents=True, exist_ok=True)
        (Path(directory) / REPORT_FILE).write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    except Exception as exc:  # noqa: BLE001
        report.setdefault("warnings", []).append("could not write {}: {}".format(REPORT_FILE, exc))


def run_import(args):
    """Glue: plan → (inspect | execute) → report dict, printed as JSON and written to <dir>/import-report.json."""
    args = dict(args or {})
    mode = args.get("mode", "inspect")
    directory = args.get("dir")
    report = {"ok": False, "status": "refused", "mode": mode, "dir": directory, "reasons": [], "warnings": []}
    try:
        if mode not in ("inspect", "execute"):
            raise RefuseImport("mode must be 'inspect' or 'execute', got {!r}".format(mode))
        if not directory:
            raise RefuseImport("args['dir'] is required")
        plan = plan_import(directory)
        report["slug"] = plan["slug"]
        report["plan"] = plan
        report["warnings"] = list(plan["warnings"])
        if args.get("strict") and plan["flagged"]:
            raise RefuseImport("strict: flagged features {}".format(", ".join(plan["flagged"])))
        adsk = _adsk()
        if adsk is None:
            raise RefuseImport("the Fusion API (adsk) is not available: run this through the Fusion MCP or the Scripts dialog")
        app = adsk.core.Application.get()
        product = app.activeProduct
        design = adsk.fusion.Design.cast(product) if product is not None else None
        if mode == "execute" and args.get("new_document"):
            doc = app.documents.add(adsk.core.DocumentTypes.FusionDesignDocumentType)
            if doc is None:
                raise RefuseImport("documents.add returned None")
            design = adsk.fusion.Design.cast(app.activeProduct)
            report["new_document"] = True
        if design is None:
            raise RefuseImport("No active Fusion design (open a design, or pass new_document=True)")
        info = inspect_design(adsk, design, plan)
        report["inspect"] = info
        if mode == "inspect":
            report["ok"] = True
            report["status"] = "inspected"
            return report
        if info["collisions"] and not args.get("force"):
            raise RefuseImport(
                ["name collision, not tagged ccpart:{}: {} (pass force=True to overwrite)".format(plan["slug"], c) for c in info["collisions"]]
            )
        if info["timeline_rolled_back"]:
            raise RefuseImport(
                "timeline is rolled back (marker {} of {}): move the marker to the end first".format(
                    info["timeline_marker"], info["timeline_count"]
                )
            )
        result = execute(adsk, plan, design, args, directory, info)
        report["result"] = result
        report["warnings"] = result["warnings"]
        report["ok"] = result["ok"]
        report["status"] = "executed" if result["ok"] else "failed"
        if not result["ok"]:
            report["reasons"] = [result.get("error", "").strip().splitlines()[-1] if result.get("error") else "failed"]
        return report
    except RefuseImport as exc:
        report["reasons"] = exc.reasons
        return report
    except Exception:  # noqa: BLE001 — never let an exception escape into the MCP call
        report["status"] = "failed"
        report["reasons"] = [traceback.format_exc().strip().splitlines()[-1]]
        report["error"] = traceback.format_exc()
        return report
    finally:
        if directory:
            _write_report(directory, report)
        if PRINT_REPORT:
            try:
                print(json.dumps(report, ensure_ascii=False))
            except Exception:  # noqa: BLE001
                pass


def report_summary(report):
    """Human lines for the closing message box / the skill's report."""
    lines = ["{}: {}".format(report.get("status", "?"), report.get("slug", ""))]
    for r in report.get("reasons") or []:
        lines.append("  " + r)
    res = report.get("result") or {}
    for key in ("created", "updated", "kept", "refreshed", "skipped"):
        if res.get(key):
            lines.append("{} ({}): {}".format(key, len(res[key]), ", ".join(n.split(" ", 1)[1] for n in res[key])))
    if res.get("previous"):
        lines.append("previous expressions (restore by hand if needed): " + ", ".join("{}={}".format(k, v["expression"]) for k, v in res["previous"].items()))
    if res.get("group"):
        lines.append("timeline group: " + res["group"])
    if res.get("rollback"):
        lines.append("rolled back: {}; could NOT delete: {}".format(", ".join(res["rollback"]["deleted"]) or "-", ", ".join(res["rollback"]["failed"]) or "-"))
    for w in report.get("warnings") or []:
        lines.append("warning: " + w)
    if res.get("canvas_note"):
        lines.append(res["canvas_note"])
    return "\n".join(lines)


STANDALONE_FILTER = "Caliper Companion export (*.ccpart.zip;features.json);;All files (*.*)"


def run_standalone(imports_dir=DEFAULT_IMPORTS_DIR):
    """The no-Claude path (Utilities → Scripts and Add-Ins → Run): file dialog → stage + pHYs → plan →
    inspect → OK/Cancel message box → execute → summary message box. Same planner, same executor, same
    import-report.json as the MCP path; message boxes are allowed here because no MCP call is waiting."""
    adsk = _adsk()
    if adsk is None:
        return {"ok": False, "status": "refused", "reasons": ["the Fusion API (adsk) is not available"]}
    ui = None
    try:
        app = adsk.core.Application.get()
        ui = app.userInterface
        dlg = ui.createFileDialog()
        dlg.title = "Caliper Companion export (.ccpart.zip or features.json)"
        dlg.filter = STANDALONE_FILTER
        dlg.isMultiSelectEnabled = False
        if dlg.showOpen() != adsk.core.DialogResults.DialogOK:
            return {"ok": False, "status": "cancelled", "reasons": ["no file chosen"]}
        chosen = dlg.filename
        try:
            plan, directory = extract_bundle(chosen, imports_dir)
        except RefuseImport as exc:
            ui.messageBox("Cannot import {}:\n\n{}".format(chosen, "\n".join(exc.reasons)), "Caliper Companion import")
            return {"ok": False, "status": "refused", "reasons": exc.reasons}
        inspect_report = run_import(default_args("inspect", directory))
        if not inspect_report["ok"]:
            ui.messageBox("Cannot import:\n\n" + "\n".join(inspect_report["reasons"]), "Caliper Companion import")
            return inspect_report
        info = inspect_report["inspect"]
        if info["collisions"]:
            ui.messageBox(
                "These names already exist in the design and were not created by a Caliper Companion import of "
                "{}:\n\n{}\n\nRename or remove them (or import into a new document) and run again.".format(
                    plan["slug"], "\n".join(info["collisions"])
                ),
                "Caliper Companion import",
            )
            return {"ok": False, "status": "refused", "reasons": ["name collision: " + c for c in info["collisions"]], "plan": plan, "inspect": info}
        if info["timeline_rolled_back"]:
            ui.messageBox("The timeline is rolled back (marker {} of {}). Move the marker to the end and run again.".format(info["timeline_marker"], info["timeline_count"]), "Caliper Companion import")
            return {"ok": False, "status": "refused", "reasons": ["timeline is rolled back"], "plan": plan, "inspect": info}
        prompt = (
            plan_summary(plan)
            + "\n\nDesign: {} ({}) · component: {}{}\n".format(
                info["document"], info["design_type"], info["component"], " (root)" if info["component_is_root"] else ""
            )
            + ("Existing entities to be touched: " + ", ".join("{} {} → {}".format(t["kind"], t["name"], t["action"]) for t in info["touched"]) + "\n" if info["touched"] else "")
            + ("This design already contains work.\n" if info["has_user_work"] else "")
            + "\nImport into this design?"
        )
        answer = ui.messageBox(
            prompt,
            "Caliper Companion import — {}".format(plan["part_name"]),
            adsk.core.MessageBoxButtonTypes.OKCancelButtonType,
            adsk.core.MessageBoxIconTypes.QuestionIconType,
        )
        if answer != adsk.core.DialogResults.DialogOK:
            return {"ok": False, "status": "cancelled", "reasons": ["cancelled at the confirmation"], "plan": plan, "inspect": info}
        report = run_import(default_args("execute", directory))
        ui.messageBox(report_summary(report) + "\n\nReport: {}".format(Path(directory) / REPORT_FILE), "Caliper Companion import — {}".format(report.get("status", "?")))
        return report
    except Exception:  # noqa: BLE001
        if ui is not None:
            try:
                ui.messageBox("Import failed:\n\n" + traceback.format_exc(), "Caliper Companion import")
            except Exception:  # noqa: BLE001
                pass
        return {"ok": False, "status": "failed", "reasons": [traceback.format_exc().strip().splitlines()[-1]], "error": traceback.format_exc()}


def run(context):
    """Fusion's entry point. Three cases:
      * the MCP trailing line already ran (`__ccpart` set)  → no-op, so a tool that also calls run() is harmless
      * a CCPART_ARGS global (the Scripts dialog, scripted)  → run_import(CCPART_ARGS), still no message boxes
      * neither (Utilities → Scripts and Add-Ins → Run)       → the standalone path with dialogs"""
    g = globals()
    if g.get("__ccpart") is not None:
        return
    args = g.get("CCPART_ARGS")
    if args:
        g["__ccpart"] = run_import(args)
        return
    g["__ccpart"] = run_standalone()


def stop(context):
    pass


# ---------------------------------------------------------------------------------------------------------------
# CLI (shell side; plain python3)
# ---------------------------------------------------------------------------------------------------------------


def _print_json(obj):
    sys.stdout.write(json.dumps(obj, indent=2, ensure_ascii=False) + "\n")


def main(argv=None):
    import argparse

    ap = argparse.ArgumentParser(
        prog="import_ccpart.py",
        description="Caliper Companion → Fusion 360. --dry-run/--extract/--emit run anywhere; "
        "--inspect/--execute need the Fusion API (adsk) and are meant for the Fusion MCP.",
    )
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--dry-run", metavar="ZIP|DIR|JSON", help="print the plan as JSON; exit 2 on refusal")
    g.add_argument("--extract", metavar="ZIP|DIR|JSON", help="stage into --to/<slug>/, write pHYs into the PNGs, print the plan")
    g.add_argument("--emit", metavar="DIR", help="print the code string for the MCP call (file text + trailing line)")
    g.add_argument("--inspect", metavar="DIR", help="run_import(mode=inspect) — inside Fusion only")
    g.add_argument("--execute", metavar="DIR", help="run_import(mode=execute) — inside Fusion only")
    ap.add_argument("--to", default=DEFAULT_IMPORTS_DIR, help="extraction root (default %(default)s)")
    ap.add_argument("--mode", choices=("inspect", "execute"), default="inspect", help="for --emit")
    ap.add_argument("--new-document", action="store_true", help="execute into a new design document")
    ap.add_argument("--no-group", action="store_true", help="skip the timeline group")
    ap.add_argument("--force", action="store_true", help="overwrite name collisions not tagged as ours")
    ap.add_argument("--strict", action="store_true", help="refuse flagged features instead of importing them")
    ns = ap.parse_args(argv)

    try:
        if ns.dry_run:
            _print_json(plan_import(ns.dry_run))
            return 0
        if ns.extract:
            plan, dest = extract_bundle(ns.extract, ns.to)
            out = dict(plan)
            out["dir"] = str(dest)
            _print_json(out)
            return 0
        if ns.emit:
            args = default_args(ns.mode, ns.emit, ns.new_document, not ns.no_group, ns.force, ns.strict)
            sys.stdout.write(mcp_code(args))
            return 0
        mode = "inspect" if ns.inspect else "execute"
        args = default_args(mode, ns.inspect or ns.execute, ns.new_document, not ns.no_group, ns.force, ns.strict)
        report = run_import(args)  # prints itself
        return 0 if report.get("ok") else 2
    except RefuseImport as exc:
        _print_json({"ok": False, "status": "refused", "reasons": exc.reasons})
        return 2


if globals().get("__name__") == "__main__":
    sys.exit(main())
