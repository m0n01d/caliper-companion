# Fusion import skill — spec review (before build)

Reviewed: `docs/fusion/IMPORT-SKILL-SPEC.md` @ `e17db11` against `SPEC.md` §1/§6.2/§7/§8a A7+A10,
`fixtures/hinge_pin/features.json`, the `fusion-api-cookbook` skill (SKILL.md + `references/snippets.md`),
`fusion-re-playbook`, and both CLAUDE.md files. Line numbers below are the spec's.

## Verdict

**BUILD WITH CHANGES.** Three blockers, all cheap to fix in the spec before code: (B1) "replace sketches by
name" on re-import deletes the user's own sketch geometry and everything extruded from it; (B2) the canvas
call as written is not the Fusion API and the "100 mm" sizing has no known pixel→cm mapping to compute from;
(B3) the MCP execution mechanism (how the path gets in, how the report gets out, who calls `run`) is
unspecified, so the "one self-contained file" cannot actually be run yet. Everything else is should/nit.

## Findings

### Blockers

**B1 · L65–68, L109–110 · Replace-by-name destroys user work.** The sketch is created empty *so the user
draws in it* (L56–57). On re-export the spec deletes the sketch named `top` and recreates it. `Sketch.deleteMe()`
takes dependent features (extrudes, holes) with it — cookbook §Trap 2 (no transactions), and the cookbook's
idempotency rule says "look up by name before creating", not "delete". Same for a canvas the user has already
calibrated: delete-and-recreate loses the calibration transform.
Fix: **parameters upsert; sketches are kept if present (never deleted, never touched); canvases are refreshed** —
delete and re-add only the canvas, and copy `old.transform` onto the new `CanvasInput` when the PNG pixel size is
unchanged, so a calibration survives a re-export. Report "kept"/"refreshed"/"created" per entity. This still
satisfies decision §7.2's intent (refresh, never duplicate). Text at §Rewrites/R2.

**B2 · L58–61, L107 · The canvas API and the 100 mm sizing.** The cookbook has no canvas snippet; from the
API reference as I know it (verify — checklist V4–V8): the factory is `component.canvases.createInput(imageFilename,
planarEntity)` (no static `CanvasInput.create`; image path first), then `canvases.add(input)`; `CanvasInput`/`Canvas`
carry `opacity` (int 0–100, so `60` not `0.6`), `transform` (a `Matrix2D` in the plane's 2-D space),
`isDisplayedThrough`, `isFlippedHorizontal/Vertical`, `name`, `deleteMe()`, `timelineObject`. The initial size at
identity transform is derived from the image's DPI metadata, and the app's PNGs come from `canvas.toBlob`, which
writes **no pHYs chunk** — so the width you get for a 1600 px image is whatever Fusion assumes for DPI-less
files, which is exactly what nobody in this repo knows. `Canvas` exposes no bounding box to read it back.
Fix: pick one of two routes and verify it once in Text Commands (V6): (a) **pHYs route** — the extraction step
writes a pHYs chunk into the *copy* of the PNG so that pixels-per-metre = `png_width_px / 0.1`; if Fusion honours
pHYs, identity transform gives 100 mm exactly, no matrix maths; (b) **matrix route** — measure the identity width
`W0` (cm) once for a DPI-less PNG of known pixel width, derive the assumed DPI, and set a uniform `Matrix2D` scale
`s = 10 / W0` per image. Route (a) is preferred (robust to Fusion changing its default). Either way: "height from
the aspect" is automatic under uniform scale; "placed at the plane origin" should read "centred on the plane
origin (Fusion's default placement — verify V7)"; and the PNG's real pixel width is `pixelWidth × renderScale`
(`FeaturesDocument.res` L69–71) — read IHDR from the file (8 bytes at offset 16, stdlib), don't trust the JSON.

**B3 · L20–25, L99 · How the script actually runs through the MCP.** "Name discovered at run time" is fine, but
the spec never says how the zip path enters a script that Fusion `exec`s as a code string, whether the tool calls
`run(context)` itself, how the report comes back, or that `ui.messageBox` (cookbook scaffold) is a modal that
freezes the in-process call. Fix — the mechanism (paste as new spec §1b, text at R1):
1. Shell side (Claude Code, plain `python3`): `import_ccpart.py extract <zip> --to ~/.caliper-companion/imports/`
   unzips to `<slug>/`, prints the plan (`--dry-run` view). Fusion never touches the zip or `~/Downloads` (see S9).
2. Fusion side, two MCP calls, both by sending `file text + "\n__ccpart = run_import(" + repr(args) + ")\n"`
   (never an f-string with the path; `repr(dict)` is a Python literal, `json.dumps` is not — `true`/`null`).
   `args = {"mode": "inspect"|"execute", "dir": ..., "new_document": bool, "group": bool}`.
   `inspect` is read-only: returns design name, `designType`, active component, timeline count, user-parameter count,
   doc length unit, and every existing param/sketch/canvas whose name the plan would touch (with ownership, S1).
   The skill shows plan + inspect result, gets confirmation, then sends `execute`.
3. Report channel: `run_import` returns a dict, `print`s it as JSON, **and writes `<dir>/import-report.json`** —
   the file is the channel the skill reads, whatever the tool does with stdout/return values.
4. `run(context)` stays as a thin wrapper reading a `CCPART_ARGS` global (for the Scripts dialog) and is a no-op
   without it, so a tool that auto-invokes `run` is harmless. Guard the CLI with
   `globals().get("__name__") == "__main__"` — under `exec(code, {})` a bare `__name__` raises `NameError`.
5. No `messageBox` anywhere on the MCP path; all errors go into the report.

### Should

**S1 · L65–68 · Ownership, not names.** `itemByName` on sketches/canvases returns the first match; a user sketch
called `top` or a parameter `wall` from *another part* imported into the same document would be silently
overwritten. Two parts with the same feature names into one document (`overall_l` twice) corrupts the first
model. Fix: tag what the import owns — parameter comment ends with `· ccpart:<slug>`; sketches/canvases get
`entity.attributes.add("caliper-companion", "slug", slug)` (verify V10). On a name hit that is *not* ours,
`inspect` reports a collision and the skill stops to ask; `execute` refuses without `force: true`.

**S2 · L62, L74 · Timeline group guards.** `timelineGroups.add` (snippet #7) only works in a parametric design —
guard `design.designType == adsk.fusion.DesignTypes.ParametricDesignType`, else skip the group and say so.
Parameter edits create no timeline items, so a re-import that only changes values produces an empty range: keep
the snippet's `end >= start` guard. If `timeline.markerPosition != timeline.count` (user rolled back) new items
land mid-history — refuse in `inspect`. On re-import the kept sketches stay in the old group and only new canvases
can be grouped: name groups `{slug} import {exportedAt}` so two groups are distinguishable. Nested/overlapping
groups fail (V11).

**S3 · L76–77 · Trap 5 is only half-handled.** "Single-component → rootComponent" is the cookbook line, but the
spec says nothing when `root.occurrences.count > 0`. Fix: target `design.activeComponent` (what the user has
activated) and take planes from *that* component (`comp.xYConstructionPlane`, `comp.sketches`, `comp.canvases`) —
creation in definition space, cookbook snippet #11's "CREATE in component space". `inspect` names the target
component; confirmation shows it.

**S4 · L46–51 · Parameter upsert details.** Update `comment` and `unit` as well as `expression` (`Parameter.comment`
and `.unit` are read/write — V2); the cookbook idiom updates expression only. Treat `userParameters.add()`
returning `None` as failure (cookbook ladder #3). Format values as `f"{v:.4f}".rstrip("0").rstrip(".")`, never
`str(float)` — `repr` can emit `1e-05`-style strings that Fusion won't parse; the app's 4 dp rounding makes this
lossless. Feature `kind` (`length|diameter|depth`) is currently unused — put it in the comment
(`diameter ±0.05 mm · faces: top · ccpart:norcold_freezer_hinge_pin`); `faceIds` must resolve through `faces[].id`,
an unknown id is a refusal (hand-edited JSON).

**S5 · L52–53 · Name reserved list is short for Fusion.** §6.2's regex admits `d1`, `d12` (Fusion's auto-named model
parameters) and unit names `mm`, `cm`, `m`, `in`, `ft`, `deg`, `rad`. The planner should refuse `^d\d+$` and the
unit names in addition to the §6.2 functions (V3 confirms what Fusion itself rejects; the app should adopt the same
list — file an app-side nit).

**S6 · L95–103 · Tests miss the executor, where the silent failures live.** `test_plan.py` + `--dry-run` never
exercise a single `adsk` call. Add: (1) `fixtures/hinge_pin.plan.json` golden snapshot, test asserts planner output
== snapshot byte-for-byte (also the `--dry-run` contract); (2) a **fake `adsk` recorder** (`tests/fake_adsk.py`,
stdlib) installed via `sys.modules` before importing the executor — attribute typos raise, every call is logged;
golden `fixtures/hinge_pin.calls.json` catches wrong plane, wrong unit arg, wrong arg order, forgotten
`created.append`; (3) re-import on the fake: second run adds no params, deletes no sketch, refreshes canvases and
carries the old transform; (4) rollback: fake raises on the 2nd canvas → `deleteMe` in reverse on exactly the
created list, report names the failure; (5) `compile()` of `file + trigger line` with a path containing a space,
quote and `é`; (6) inspect-mode collision fixture. Live test stays as written, plus the V-checklist below.

**S7 · L72–73 · "Design that already contains user work" is undefined.** Define it in `inspect`:
`timeline.count > 0 or userParameters.count > 0 or root.occurrences.count > 0`. A previous import counts (it always
confirms on re-import — good). "Offers a new document": `app.documents.add(FusionDesignDocumentType)` inside
`execute` when `new_document` is true, then re-resolve `design` from the new doc; note the doc is unsaved and
A10's `path` save is v1.

**S8 · L85 · `flagged`: proceed is the right call**, given SPEC §7/M5 ("never silently averaged" — the app
already refused to hide it; the parameter is a starting value). Two conditions to keep it honest: flagged
features are listed in the *confirmation* (before the design is touched), not only the report, and the comment
prefix is `FLAGGED …` as written. Offer `--strict` to refuse instead; default proceed.

**S9 · not in spec · macOS TCC and image lifetime.** Fusion reading `~/Downloads` in-process triggers the
"Fusion wants access to your Downloads folder" prompt on first use, which blocks the MCP call behind a dialog.
The shell-side extraction to `~/.caliper-companion/imports/<slug>/` (B3.1) sidesteps it — hidden home dirs are not
TCC-protected. Do not use `tempfile.TemporaryDirectory` in Fusion's process. Whether Fusion embeds the canvas
image or references the path is V9; until verified, keep the extraction dir and tell the user not to delete it.

### Nits

- **N1 · L15** — don't copy the golden into the skill; the skill lives in this repo (L18–19), reference
  `fixtures/hinge_pin/features.json` and build the test zip at test time with `zipfile` (no binary in git).
- **N2 · L57** — an uncalibrated canvas next to correct parameters invites tracing at the wrong scale; make the
  status visible in Fusion, not only the report: name it `top_photo_uncalibrated` until the user calibrates
  (or at least put "uncalibrated, nominal 100 mm" in the group name).
- **N3 · L29–30** — the golden has no `part.path` yet (A10 not built); planner reads `path` as `""` when absent.
- **N4 · L87** — also refuse `features` empty? No — a part with faces and no dimensions is a valid "photos only"
  import; warn instead. Do refuse `value <= 0` or non-finite values (hand-edited JSON).
- **N5 · L99** — the cookbook's `isComputeDeferred` is unnecessary here (nothing computes); don't use it, one
  less way to leave the design dirty. One script for ≤ 6 faces is comfortably under the ~10 s line; warn above 8.
- **N6 · language** — Python is right (`claude-conventions` "Python for scripts … automation"; the Fusion API is
  Python in-process). Stdlib only; no npm change. Run tests as `python3 -m unittest discover .claude/skills/fusion-import/tests`.
- **N7 · L54–55** — a sketch on `xZConstructionPlane` is viewed mirrored from the Front view in Fusion; the
  canvas may come in flipped — that is what `isFlippedHorizontal` is for (V8).

## Verify in Text Commands before trusting (paste into SKILL.md)

Fusion updates monthly; the cookbook's rule is "trust the live API". Run in View → Show Text Commands, Py mode,
on a scratch document, before the first live import each month:

- [ ] **V1** `design.userParameters.add("overall_l", ValueInput.createByString("42.18 mm"), "mm", "c")` returns
      a `UserParameter` (not `None`); `add("t", createByString("1.375 in"), "in", "c")` too.
- [ ] **V2** `p.expression = "42.20 mm"`, `p.comment = "x"`, `p.unit = "in"` all stick (read back).
- [ ] **V3** `add("d1", …)`, `add("mm", …)`, `add("in", …)` — which raise, which return `None`, which succeed.
- [ ] **V4** `root.canvases.createInput(png_path, root.xYConstructionPlane)` — confirm factory name and argument
      order (image first?); confirm there is no `adsk.fusion.CanvasInput.create`.
- [ ] **V5** `ci.opacity = 60` (int); `canvases.add(ci)` returns a `Canvas`; `c.name = "top_photo"` sticks;
      `c.deleteMe()` returns `True`; `c.timelineObject` is not `None` (canvases are timeline items).
- [ ] **V6** Insert a DPI-less 1600×1200 PNG at identity transform; draw a 100 mm construction line on the same
      plane; measure the canvas width (Inspect → Measure on canvas edges, or visually against the line). Record
      `W0`. Then insert the same PNG with a pHYs chunk (16000 px/m) — is it 100 mm wide? Decide route (a)/(b).
- [ ] **V7** Where is the canvas placed at identity: centred on the origin, or corner at origin?
- [ ] **V8** Same PNG on `xZConstructionPlane` and `yZConstructionPlane`: which way is up from Front / Right?
      Does `isFlippedVertical` fix it?
- [ ] **V9** Delete the PNG from disk, save, close, reopen: canvas still renders? (embedded vs referenced.)
- [ ] **V10** `sketch.attributes.add("caliper-companion","slug","x")` and the same on a `Canvas`; read back with
      `attributes.itemByName`; `design.findAttributes("caliper-companion","slug")` finds both.
- [ ] **V11** `timelineGroups.add(s, e)` over a range that includes an existing group → error? Group name with
      spaces/colon sticks? `TimelineGroup.deleteMe(False)` dissolves without deleting members?
- [ ] **V12** `design.activeComponent` when a sub-component is activated; `comp.sketches.add(comp.xYConstructionPlane)`
      lands in that component.
- [ ] **V13** In a Direct-modeling document: `design.designType`, and `timelineGroups.add` behaviour.
- [ ] **V14** The MCP script tool: does it call `run(context)` itself? Is stdout returned? Is a `NameError` on
      `__name__` raised under its `exec`? (Send a 3-line probe before the real script.)

## Rewrites (ready to paste)

**R1 — new §1b "Execution mechanism"** (after L25):

> `import_ccpart.py` has four entry points: `plan(path)` (pure), `execute(plan, design, args)` (adsk),
> `run_import(args: dict) -> dict` (glue, adsk) and `run(context)` (Scripts-dialog wrapper; no-op without a
> `CCPART_ARGS` global). The skill never passes a path through an f-string: it sends the file's text followed by
> `__ccpart = run_import(<repr(args)>)`. Two calls per import — `mode: "inspect"` (read-only; returns design type,
> active component, timeline/parameter counts, doc units, and any existing entity the plan would touch, with
> ownership) and, after confirmation, `mode: "execute"`. The zip is unzipped by the skill on the shell side into
> `~/.caliper-companion/imports/<slug>/`; Fusion only ever reads that directory. `run_import` returns the report,
> prints it as JSON, and writes `<dir>/import-report.json`, which the skill reads. No `ui.messageBox` on the MCP
> path; every error is a report entry.

**R2 — replace L65–68 "Idempotent by name":**

> **Idempotent by ownership.** Every entity the import creates is tagged (`· ccpart:<slug>` in a parameter's
> comment; a `caliper-companion/slug` attribute on sketches and canvases). Parameter exists and is ours → update
> expression, unit, comment. Sketch exists and is ours → **kept, untouched** (the user's geometry lives there).
> Canvas exists and is ours → deleted and re-added from the new PNG, carrying over its previous `transform` when the
> pixel size is unchanged (a calibration survives). Name exists but is *not* ours → collision: `inspect` lists
> it, the skill asks, `execute` refuses without `force`. The header of the script states all of this.

**R3 — replace L58–61 "Canvas size":**

> **Canvas size**: the photo is a sketch, not a measurement (SPEC §1), so there is no true scale. The canvas is
> centred on the plane origin at a nominal **100 mm** width, uniform scale (height follows), opacity 60, and
> `top_photo_uncalibrated` as its name until the user calibrates it in Fusion. The mechanism is fixed by V6: either
> a pHYs chunk written into the extracted PNG copy (preferred) or a uniform `Matrix2D` scale derived from the
> measured identity width. The PNG's real pixel width is read from its IHDR (= `pixelWidth × renderScale`), not
> from the JSON. No scale is ever derived from dimensions.

**R4 — add to §5 refusals table:**

> | `inspect` finds a name collision not tagged `ccpart:<slug>` | refuse unless `force`, list the names |
> | `timeline.markerPosition != timeline.count` | refuse ("timeline is rolled back") |
> | `faceIds` entry not in `faces[]`, `value <= 0` or non-finite | refuse, name the feature |
> | design is Direct-modeling | proceed, skip the timeline group, warn |
