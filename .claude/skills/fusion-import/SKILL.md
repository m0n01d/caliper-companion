---
name: fusion-import
description: Import a Caliper Companion export (<slug>.ccpart.zip or features.json) into Fusion 360 through the Fusion MCP — one named user parameter per feature, one empty sketch per face with the dimensioned photo attached as a canvas, tagged so a re-export refreshes in place. Use when the user says "import this part into Fusion", mentions a .ccpart / .ccpart.zip / features.json, or a "caliper companion export".
---

# Fusion import (Caliper Companion → Fusion 360)

The app ends at `<slug>.ccpart.zip`; this skill turns it into **named user parameters** (one per feature,
`overall_l = 42.18 mm`, comment with tolerance, faces and the `ccpart:<slug>` tag) and **one empty sketch per
face** on the plane its kind implies (top/detail → XY, side → XZ, end → YZ) with the dimensioned PNG as a
**canvas** (`<label>_photo`, nominal 100 mm wide, opacity 60). Never geometry, never a scale derived from
the photo — SPEC §1: the caliper is the only source of numbers, the photo is a labeled sketch.

Everything lives in one file, `scripts/import_ccpart.py` (planner + executor + CLI; spec in
`docs/fusion/IMPORT-SKILL-SPEC.md`). Read the `fusion-api-cookbook` skill before touching the executor.

## With Claude (the Fusion MCP)

Prerequisites: the Fusion MCP is connected and Fusion has the target design open (or the user wants a new
document); the export is on this Mac (`~/Downloads/<slug>.ccpart.zip` is the usual place, any path works).

1. **Stage on the shell side** (plain `python3`, no Fusion). This unzips into
   `~/.caliper-companion/imports/<slug>/`, writes a pHYs chunk into each `*_dimensioned.png` copy (so
   Fusion sizes the canvas to 100 mm), drops any stale report, and prints the plan:

   ```sh
   python3 .claude/skills/fusion-import/scripts/import_ccpart.py --extract ~/Downloads/<slug>.ccpart.zip
   ```

   Exit 2 = refusal (`reasons[]` says why; see Refusals). Fusion never reads `~/Downloads` (macOS TCC
   prompt) — only the staging folder. Tell the user not to delete it until V9 says canvases are embedded.

2. **Inspect (read-only MCP call).** Build the code string and send it with the Fusion MCP's Python
   script/code-execution tool (find its name at run time; never hard-code it):

   ```sh
   python3 .claude/skills/fusion-import/scripts/import_ccpart.py --emit "<dir>" --mode inspect
   ```

   The string is the whole file followed by exactly one trailing line, e.g.

   ```python
   __ccpart = run_import({'mode': 'inspect', 'dir': '/Users/dwight/.caliper-companion/imports/norcold_freezer_hinge_pin', 'new_document': False, 'group': True, 'force': False, 'strict': False})
   ```

   `repr(args)` is a Python literal, so paths with spaces, quotes or non-ASCII survive; never build this
   line with an f-string or `json.dumps`. `run_import` returns the report, prints it as one JSON line,
   and writes `<dir>/import-report.json` — **read the file**, whatever the tool does with stdout.

3. **Show the plan and the inspect result, then ask.** Always confirm; the design almost always has
   user work (`inspect.has_user_work`: timeline, parameters or occurrences — a previous import counts).
   Show: N parameters (name = expression), M sketches (plane), canvases, every `warnings[]` line
   (FLAGGED features go here, before the design is touched), the target component (`inspect.component`,
   root or not), `design_type`, and `inspect.touched[]` — what already exists and what happens to it
   (`update` / `keep` / `refresh`). If `inspect.collisions[]` is non-empty, **stop and ask**: those names
   exist but were not created by an import of this part; `force: True` overwrites them, otherwise the
   user renames them or picks a new document (`new_document: True`, unsaved; the A10 folder save is v1).
   If `timeline_rolled_back`, ask the user to move the marker to the end first.

4. **Execute** — same call with `--mode execute` (plus `--new-document`, `--no-group`, `--force`,
   `--strict` as decided). Then read `<dir>/import-report.json` again.

5. **Report back** from the file (`status`: `executed` / `refused` / `failed`): `result.created`,
   `updated` (with `previous` expressions for a manual restore), `kept`, `refreshed`
   (`carried_transforms` = calibrations that survived), `skipped`, `group`, `warnings`, and
   `canvas_note` — say explicitly that canvases are **uncalibrated, nominal 100 mm**, to be calibrated
   in Fusion if they should scale. On `failed`, `result.rollback.deleted` / `.failed` is the manual
   cleanup map — name anything that would not delete.

Each MCP call ends in a clean state (no deferred compute left on; `isComputeDeferred` is only used above
6 faces and always reset in `finally`). No `ui.messageBox` on this path — a modal would freeze the call.

## Without Claude (Fusion → Utilities → Scripts and Add-Ins → Run)

Same file, same planner, same executor, same `import-report.json`; dialogs instead of MCP calls.

- One-time: create `~/Library/Application Support/Autodesk/Autodesk Fusion 360/API/Scripts/import_ccpart/`
  and copy (or symlink) `scripts/import_ccpart.py` and `scripts/import_ccpart.manifest` into it, then in
  Fusion: Utilities → Add-Ins → Scripts tab → it appears as `import_ccpart` (or the green `+` and pick
  the folder).
- Run it: a file dialog filtered to `*.ccpart.zip` / `features.json` (the dialog grants file access, so
  `~/Downloads` is fine here) → staged into `~/.caliper-companion/imports/<slug>/` inside Fusion's
  Python, same pHYs rewrite → the plan (parameters, sketches, warnings, target component, anything that
  would be touched) in an **OK/Cancel** message box → OK executes → a summary message box with the
  created/updated/kept/refreshed lists, previous expressions, the canvas note and the report path.
- Collisions and a rolled-back timeline are refused with a message (no `force` on this path: rename or
  use a new document and run again). Cancel at either dialog writes nothing.

## What re-import does (idempotent by ownership)

| exists and is ours | action |
|---|---|
| parameter (comment carries `ccpart:<slug>`) | expression, unit, comment updated; previous values in the report |
| sketch (attribute `caliper-companion/ccpart`) | **kept, untouched** — your geometry lives there |
| canvas (same attribute) | new canvas added from the new PNG, old one deleted after; transform carried when the pixel size is unchanged |
| name exists, not ours | collision → `inspect` lists it, `execute` refuses without `force` |

## Refusals (before anything is touched)

Unknown `schema` (shows the string) · a feature name that fails `^[a-z][a-z0-9_]{0,31}$`, is a Fusion
function name, `d<n>`, or a unit name · `faces` empty · kind conflict / duplicate feature · `faceIds`
not in `faces[]` · `value` ≤ 0 or non-finite · `part.units` not `mm`/`in` · an `annotated` entry that
is not a PNG · no active design (unless `new_document`) · name collision without `force` · timeline
rolled back · `strict` with flagged features. Warnings (proceed): flagged feature (parameter comment
prefixed `FLAGGED spread … > ±…`), annotated file missing from the bundle (that canvas skipped), bare
`features.json` (all canvases skipped), PNG size ≠ `pixelWidth × renderScale` (the PNG wins), no
features (photos-only), Direct-modeling design (no timeline group), more than 8 faces (slow call).

## Report shape

```json
{"ok": true, "status": "executed", "mode": "execute", "dir": "…/imports/<slug>", "slug": "…",
 "plan": {"parameters": [{"name","expression","unit","comment","kind","flagged"}], "sketches": [{"name","kind","plane","canvas_file","canvas_name","png_width","png_height"}], "group_name": "<slug> import", "warnings": []},
 "inspect": {"document","design_type","component","component_is_root","length_unit","timeline_count","timeline_marker","timeline_rolled_back","user_parameters","occurrences","has_user_work","touched": [],"collisions": []},
 "result": {"component","created": [],"updated": [],"kept": [],"refreshed": [],"skipped": [],"previous": {},"carried_transforms": [],"group","warnings": [],"canvas_note","rollback": {"deleted": [],"failed": []}},
 "reasons": [], "warnings": []}
```

## First run on a new Fusion version: verify in Text Commands

Fusion updates monthly; the cookbook's rule is "trust the live API". Run in View → Show Text Commands,
Py mode, on a scratch document, before the first live import each month. The script's assumptions are
in brackets.

- [ ] **V1** `design.userParameters.add("overall_l", ValueInput.createByString("42.18 mm"), "mm", "c")` returns
      a `UserParameter` (not `None`); `add("t", createByString("1.375 in"), "in", "c")` too.
- [ ] **V2** `p.expression = "42.20 mm"`, `p.comment = "x"`, `p.unit = "in"` all stick (read back).
      [executor sets expression, then unit, then comment]
- [ ] **V3** `add("d1", …)`, `add("mm", …)`, `add("in", …)` — which raise, which return `None`, which succeed.
      [planner refuses all three up front]
- [ ] **V4** `root.canvases.createInput(png_path, root.xYConstructionPlane)` — confirm factory name and argument
      order (image first?); confirm there is no `adsk.fusion.CanvasInput.create`. [image path first, plane second]
- [ ] **V5** `ci.opacity = 60` (int); `canvases.add(ci)` returns a `Canvas`; `c.name = "top_photo"` sticks;
      `c.deleteMe()` returns `True`; `c.timelineObject` is not `None` (canvases are timeline items).
      Also: `comp.canvases.itemByName("top_photo")` exists (the script falls back to a linear scan if not);
      `c.transform.copy()` returns a `Matrix2D`; `ci.transform = m` is accepted on a `CanvasInput`.
- [ ] **V6** Insert a DPI-less 1600×1200 PNG at identity transform; draw a 100 mm construction line on the same
      plane; measure the canvas width (Inspect → Measure on canvas edges, or visually against the line). Record
      `W0`. Then insert the same PNG with a pHYs chunk (16000 px/m — `--extract` writes exactly this) — is it
      100 mm wide? [pHYs route assumed; if Fusion ignores pHYs, switch to the matrix route: uniform scale
      `10 / W0` on `ci.transform`]
- [ ] **V7** Where is the canvas placed at identity: centred on the origin, or corner at origin?
- [ ] **V8** Same PNG on `xZConstructionPlane` and `yZConstructionPlane`: which way is up from Front / Right?
      Does `isFlippedVertical` fix it?
- [ ] **V9** Delete the PNG from disk, save, close, reopen: canvas still renders? (embedded vs referenced.)
      Until known, keep `~/.caliper-companion/imports/<slug>/`.
- [ ] **V10** `sketch.attributes.add("caliper-companion","ccpart","x")` and the same on a `Canvas`; read back with
      `attributes.itemByName("caliper-companion","ccpart")`; `design.findAttributes("caliper-companion","ccpart")`
      finds both. [ownership check depends on this]
- [ ] **V11** `timelineGroups.add(s, e)` over a range that includes an existing group → error? Group name with
      spaces sticks? `TimelineGroup.deleteMe(False)` dissolves without deleting members? [the script groups
      only the items it created, found via `entity.timelineObject.index` after any old-canvas deletion]
- [ ] **V12** `design.activeComponent` when a sub-component is activated; `comp.sketches.add(comp.xYConstructionPlane)`
      lands in that component. [target is always `activeComponent`]
- [ ] **V13** In a Direct-modeling document: `design.designType`, and `timelineGroups.add` behaviour.
      [group skipped when not `ParametricDesignType`]
- [ ] **V14** The MCP script tool: does it call `run(context)` itself? Is stdout returned? Is a `NameError` on
      `__name__` raised under its `exec`? (Send a 3-line probe before the real script.) [`run()` is a no-op
      once `__ccpart` exists; the CLI guard uses `globals().get("__name__")`; the report file is the channel]
- [ ] **V15** Standalone path: the script shows up under Scripts with the shipped `.manifest`;
      `ui.createFileDialog()` accepts the filter string `Caliper Companion export (*.ccpart.zip;features.json);;All files (*.*)`
      and `showOpen()` returns `DialogResults.DialogOK` with `filename` set; `ui.messageBox(text, title,
      MessageBoxButtonTypes.OKCancelButtonType, MessageBoxIconTypes.QuestionIconType)` returns
      `DialogResults.DialogOK` on OK.

## Limits

- No geometry, no scale: sketches are empty, canvases nominal 100 mm until calibrated by hand.
- v0 reads the exported file; v1 pulls `features.json` from CouchDB over HTTP (SPEC §7) and saves the design
  into the Fusion project folder named by `part.path` (SPEC §8a A10) — same planner, an extra executor step.
- Fusion has no transactions: a failure mid-run rolls back what this run created; updated parameters are
  restored by hand from `result.previous`; a canvas refresh that fails after the new canvas exists keeps
  the old one.

## Tests

```sh
python3 -m unittest discover -s .claude/skills/fusion-import/tests   # 84 tests, no Fusion needed
UPDATE_GOLDEN=1 python3 -m unittest discover -s .claude/skills/fusion-import/tests   # accept snapshot changes
python3 .claude/skills/fusion-import/scripts/import_ccpart.py --dry-run fixtures/hinge_pin/features.json
```

`tests/golden/hinge_pin.plan.json` is the plan for the fixture zip (also the `--dry-run` contract);
`hinge_pin.calls.json` is every `adsk` call the executor makes for it, recorded by `scripts/fake_adsk.py`.
