# Fusion import skill — spec (v0, for review)

The other half of `SPEC.md` §7. The app ends at `<slug>.ccpart.zip`; this skill turns that zip into
named user parameters and per-face sketches with the annotated photo attached, inside Fusion 360,
through the Fusion MCP. Status: **spec, not built**. Review, then build.

## 1. Where it lives and how it runs

```
caliper-companion/
  .claude/skills/fusion-import/
    SKILL.md                 # the Claude Code skill: when to use, steps, what to confirm
    scripts/import_ccpart.py # ONE self-contained Fusion script (planner + executor)
    tests/test_plan.py       # stdlib unittest on the planner, runs without Fusion
    fixtures/                # golden features.json copy + a tiny fake zip for tests
```

- A **project skill** in this repo, so any Claude Code session on the Mac with the Fusion MCP
  connected can use it, and it lives next to the JSON contract it consumes.
- The skill drives the Fusion MCP's script-execution tool (name discovered at run time; the skill
  never hard-codes it). One script, one call, ending in a clean state (cookbook: in-process,
  no deferred-compute left behind).
- `import_ccpart.py` is a single file so the MCP can run it as one unit: a pure **planner**
  (zip/JSON → plan) and a Fusion **executor** (plan → parameters, sketches, canvases). The
  `adsk` import is guarded so the planner runs under plain Python for tests and dry runs.

## 2. Input

- A path to `<slug>.ccpart.zip` (exported from the phone via Share/Files/AirDrop). Also accepts an
  unzipped folder or a bare `features.json` (then canvases are skipped with a warning).
- `features.json` per `SPEC.md` §7 + §8a A7: `schema == "caliper-companion/features/1"`, `part`,
  `faces[]` (`kind`, `label`, `image`, `annotated`, `pixelWidth`, `pixelHeight`, `renderScale`),
  `features[]` (`name`, `kind`, `value`, `tolerance`, `faceIds`, `spread`, `flagged`,
  `measurements[]`), `telemetry`.
- Anything else in the JSON is ignored. An unknown `schema` refuses with the string it saw.

## 3. Plan (pure, unit-tested)

```
zip ──► features.json ──► validate ──► plan
                                       ├─ parameters[]  {name, expression, comment}
                                       ├─ sketches[]    {name, plane, canvas_file}
                                       └─ warnings[]    (flagged, missing files, …)
```

- **Parameters**: one per feature. `expression = f"{value} {unit}"` with `unit` = `"mm"` or
  `"in"` from `part.units` (never a raw float: cookbook trap 1). `comment` =
  `"±{tolerance} {unit} · faces {labels joined} · caliper-companion"`; a flagged feature's comment
  starts with `"FLAGGED spread {spread} > ±{tolerance} · "` and is listed in `warnings`. Values are
  written verbatim from the JSON (the app already rounded to 4 dp); the skill never averages,
  rounds, or "fixes" anything.
- **Names**: feature names are already valid Fusion parameter names (`SPEC.md` §6.2). The planner
  re-validates with the same regex and reserved list and refuses on any miss, naming it.
- **Sketches**: one per face, named `label` (e.g. `top`, `left_side`), on the plane from `kind`:
  `top → xYConstructionPlane`, `side → xZConstructionPlane`, `end → yZConstructionPlane`,
  `detail → xYConstructionPlane`. The sketch is created **empty**: the skill never invents
  geometry. The dimensioned PNG becomes a **canvas** on the same plane, named `label_photo`.
- **Canvas size**: the photo is a sketch, not a measurement (SPEC §1), so there is no true scale.
  The canvas is placed at the plane origin with a nominal width of **100 mm** (height from the
  aspect) and 60 % opacity, and the run report says so; the user calibrates it in Fusion if they
  want it to scale. No attempt is made to derive scale from dimensions.
- **Timeline group** named `{slug} import` around everything the run created.

## 4. Execution rules (cookbook-compliant)

- **Idempotent by name**: parameter exists → update its expression and comment; sketch or canvas
  with the same name exists → delete and recreate (so re-import after re-export is a refresh, not
  a duplicate). The header of the script states this.
- **Rollback**: every created entity is appended to a list; on any exception, `deleteMe()` in
  reverse order, and the report names anything that would not delete. Updated (pre-existing)
  parameters are not rolled back; their previous expressions are printed so the user can restore.
- **Confirmation**: the skill shows the plan (N parameters, M sketches, warnings) and asks before
  running against a design that already contains user work; it offers a new document otherwise.
- **Report** after the run: created/updated names and counts, flagged features, the canvas-scale
  note, and the timeline group name. This is also the manual rollback map.
- Never `ValueInput.createByReal` for a length; never rely on `profiles.item(0)`; single-component
  designs work in `rootComponent` with a comment saying so.

## 5. Refusals (loud, before touching the design)

| condition | behaviour |
|---|---|
| `schema` not `caliper-companion/features/1` | refuse, show the schema string |
| a feature name fails the §6.2 rule | refuse, name it (should be impossible from the app) |
| `flagged: true` on any feature | **proceed**, mark the parameter comment, list in warnings |
| a face's `annotated` file missing from the zip | proceed, skip that canvas, warn |
| `faces` empty | refuse ("nothing to import") |
| no active Fusion design | refuse with the cookbook's message |

Kind conflicts cannot reach the skill (the app blocks export); if one appears anyway
(hand-edited JSON), refuse and name it.

## 6. Tests

- `tests/test_plan.py` (stdlib `unittest`, no Fusion): the golden `fixtures/hinge_pin/features.json`
  plans 9 parameters with expressions like `"42.18 mm"`, 3 sketches on the right planes, canvas
  names `top_photo`/`side_photo`/`end_photo`; a flagged fixture yields the FLAGGED comment and a
  warning; a wrong schema refuses; a missing annotated file warns; an inch part yields `"1.375 in"`.
- `python import_ccpart.py --dry-run path.zip` prints the plan and exits 0 with no Fusion.
- **Live test (Mac, you)**: export the fixture-based part from the phone (or the app's e2e), run the
  skill on a new document, confirm in Fusion: Parameters dialog shows the names and values in the
  document's units; each face sketch exists on its plane with its photo canvas; re-running updates
  in place with no duplicates.

## 7. Open questions for review

1. **Canvas scale**: nominal 100 mm width (recommended, honest) vs. scaling the canvas so one chosen
   feature's measured pixel distance equals its value (tempting, but it implies a precision the photo
   doesn't have and breaks on perspective; SPEC §1 says no).
2. **Re-import policy**: replace sketches/canvases by name (recommended) vs. version them
   (`top_photo_2`). Replacing keeps the model clean; versioning keeps history.
3. **Where the zip lands on the Mac**: AirDrop to `~/Downloads` is the assumed path; the skill takes
   any path.
4. **v1**: pull `features.json` from CouchDB over HTTP instead of a file (SPEC §7) — same planner.
