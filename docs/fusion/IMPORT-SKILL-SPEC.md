# Fusion import skill — spec (v0, for review)

The other half of `SPEC.md` §7. The app ends at `<slug>.ccpart.zip`; this skill turns that zip into
named user parameters and per-face sketches with the annotated photo attached, inside Fusion 360,
through the Fusion MCP. Status: **reviewed (`IMPORT-SKILL-REVIEW.md`, BUILD WITH CHANGES) and built** — the
review's rewrites R1–R4 are folded in below; the code lives in `.claude/skills/fusion-import/`.

## 1. Where it lives and how it runs

```
caliper-companion/
  .claude/skills/fusion-import/
    SKILL.md                    # the Claude Code skill: when to use, steps, what to confirm, V-checklist
    scripts/import_ccpart.py    # ONE self-contained file: planner (pure) + executor (adsk) + CLI
    scripts/fake_adsk.py        # recording fake of the adsk surface the executor uses (tests only)
    tests/test_plan.py          # stdlib unittest on the planner, pHYs writer, CLI — runs without Fusion
    tests/test_executor.py      # stdlib unittest on the executor against fake_adsk
    tests/golden/               # plan snapshot + fake-adsk call-log snapshot for the hinge_pin fixture
```

The test zip is built at test time from `fixtures/hinge_pin/features.json` (review N1: no golden copy, no
binary in git).

- A **project skill** in this repo, so any Claude Code session on the Mac with the Fusion MCP
  connected can use it, and it lives next to the JSON contract it consumes.
- The skill drives the Fusion MCP's script-execution tool (name discovered at run time; the skill
  never hard-codes it). Each call ends in a clean state (cookbook: in-process, no deferred-compute
  left behind).
- `import_ccpart.py` is a single file so the MCP can run it as one unit: a pure **planner**
  (zip/JSON → plan) and a Fusion **executor** (plan → parameters, sketches, canvases). The
  `adsk` import is guarded so the planner runs under plain Python for tests and dry runs.

### 1b. Execution mechanism (review B3)

`import_ccpart.py` has four entry points: `plan_import(path)` (pure), `execute(plan, design, args)` (adsk),
`run_import(args: dict) -> dict` (glue, adsk) and `run(context)` (Scripts-dialog wrapper; no-op without a
`CCPART_ARGS` global). The skill never passes a path through an f-string: it sends the file's text followed by
`__ccpart = run_import(<repr(args)>)`. Two calls per import — `mode: "inspect"` (read-only; returns design type,
active component, timeline/parameter counts, doc units, and any existing entity the plan would touch, with
ownership) and, after confirmation, `mode: "execute"`. The zip is unzipped by the skill on the shell side into
`~/.caliper-companion/imports/<slug>/`; Fusion only ever reads that directory. `run_import` returns the report,
prints it as JSON, and writes `<dir>/import-report.json`, which the skill reads. No `ui.messageBox` on the MCP
path; every error is a report entry.

Shell side, plain `python3`: `import_ccpart.py --extract <zip> [--to ~/.caliper-companion/imports]` unzips to
`<slug>/`, writes the pHYs chunk into each `*_dimensioned.png` copy (§3), removes any stale
`import-report.json`, and prints the plan; `--emit <dir> --mode inspect|execute [--new-document] [--no-group]
[--force] [--strict]` prints the exact code string for the MCP call (file text + trailing line). `args` is
`{"mode", "dir", "new_document", "group", "force", "strict"}`; the CLI is guarded with
`globals().get("__name__") == "__main__"` so the module-level code is inert under the tool's `exec`.

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
- **Canvas size**: the photo is a sketch, not a measurement (SPEC §1), so there is no true scale. The
  canvas is centred on the plane origin at a nominal **100 mm** width, uniform scale (height follows),
  opacity 60 (int 0–100), named `label_photo`, and the run report says it is uncalibrated until the user
  calibrates it in Fusion. The mechanism is fixed by V6: a **pHYs chunk written into the extracted PNG
  copy** (preferred; pixels-per-metre = `png_width_px / 0.1`, so an identity transform gives 100 mm if
  Fusion honours pHYs) or, as the fallback, a uniform `Matrix2D` scale derived from the measured
  identity width. The PNG's real pixel width is read from its IHDR (= `pixelWidth × renderScale`), not
  from the JSON; a disagreement is a warning. No scale is ever derived from dimensions.
- **Timeline group** named `{slug} import` around everything the run created.

## 4. Execution rules (cookbook-compliant)

- **Idempotent by ownership.** Every entity the import creates is tagged (`· ccpart:<slug>` in a
  parameter's comment; a `caliper-companion` attribute group with `ccpart = <slug>` and `face = <label>`
  on sketches and canvases). Parameter exists and is ours → update expression, unit, comment. Sketch
  exists and is ours → **kept, untouched** (the user's geometry lives there). Canvas exists and is ours
  → deleted and re-added from the new PNG, carrying over its previous `transform` when the pixel size is
  unchanged (a calibration survives). Name exists but is *not* ours → collision: `inspect` lists it, the
  skill asks, `execute` refuses without `force`. The header of the script states all of this.
- **Target component**: `design.activeComponent` (what the user has activated), planes and collections
  taken from that component (cookbook trap 5, snippet #11: create in component space); the report names
  it, and says so when it is the root.
- **Timeline group** only in a parametric design and only around what this run created (kept sketches
  stay in their old group); skipped with a warning in a Direct-modeling document. The run refuses when
  the timeline marker is not at the end (rolled back).
- **Rollback**: every created entity is appended to a list; on any exception, `deleteMe()` in
  reverse order, and the report names anything that would not delete. Updated (pre-existing)
  parameters are not rolled back; their previous expressions are printed so the user can restore.
  A refreshed canvas is created first and the old one deleted only after the new one exists, so a
  failed refresh leaves the old canvas in place.
- **Confirmation**: the skill shows the plan (N parameters, M sketches, flagged features, warnings) plus
  the `inspect` result and asks before running against a design that already contains user work
  (`timeline.count > 0 or userParameters.count > 0 or occurrences.count > 0` — a previous import counts);
  it offers a new document otherwise (`new_document: true` → `app.documents.add`, unsaved; the A10 save
  is v1).
- **Report** after the run: created/updated names and counts, flagged features, the canvas-scale
  note, and the timeline group name. This is also the manual rollback map.
- Never `ValueInput.createByReal` for a length; never rely on `profiles.item(0)`; values are formatted
  `f"{v:.4f}".rstrip("0").rstrip(".")` (never `str(float)`, which can emit `1e-05`); `userParameters.add()`
  returning `None` is a failure; `isComputeDeferred` (in `try/finally`) only above 6 faces.

## 5. Refusals (loud, before touching the design)

| condition | behaviour |
|---|---|
| `schema` not `caliper-companion/features/1` | refuse, show the schema string |
| a feature name fails the §6.2 rule, or is `d<n>` / a unit name (`mm cm m in ft deg rad`, review S5) | refuse, name it (should be impossible from the app) |
| `flagged: true` on any feature | **proceed**, mark the parameter comment, list in warnings |
| a face's `annotated` file missing from the zip | proceed, skip that canvas, warn |
| `faces` empty | refuse ("nothing to import") |
| no active Fusion design | refuse with the cookbook's message (or `new_document: true`) |
| `inspect` finds a name collision not tagged `ccpart:<slug>` | refuse unless `force`, list the names |
| `timeline.markerPosition != timeline.count` | refuse ("timeline is rolled back") |
| `faceIds` entry not in `faces[]`, `value <= 0` or non-finite | refuse, name the feature |
| design is Direct-modeling | proceed, skip the timeline group, warn |
| `features` empty | proceed ("photos only"), warn |
| `flagged: true` with `strict` | refuse, name the features |

Kind conflicts cannot reach the skill (the app blocks export); if one appears anyway
(hand-edited JSON), refuse and name it.

## 6. Tests

- `tests/test_plan.py` (stdlib `unittest`, no Fusion): the golden `fixtures/hinge_pin/features.json`
  plans 9 parameters with expressions like `"42.18 mm"`, 3 sketches on the right planes, canvas
  names `top_photo`/`side_photo`/`end_photo`; a flagged fixture yields the FLAGGED comment and a
  warning; a wrong schema refuses; a missing annotated file warns; an inch part yields `"1.375 in"`.
- `python import_ccpart.py --dry-run path.zip` prints the plan and exits 0 with no Fusion (2 on refusal);
  the output is compared byte-for-byte with `tests/golden/hinge_pin.plan.json`.
- `tests/test_executor.py` runs the executor against `scripts/fake_adsk.py` (a recording fake installed via
  `sys.modules`; attribute typos raise; every call is logged): golden call log
  `tests/golden/hinge_pin.calls.json`; re-import on a pre-populated fake (parameters updated, sketches kept,
  canvases refreshed with the old transform carried); ownership collision refuses before any write; a
  mid-run exception rolls back exactly the created entities in reverse order; `compile()` of the emitted
  MCP code with a spaced/quoted/unicode path; the pHYs writer produces a valid PNG.
- **Live test (Mac, you)**: export the fixture-based part from the phone (or the app's e2e), run the
  skill on a new document, confirm in Fusion: Parameters dialog shows the names and values in the
  document's units; each face sketch exists on its plane with its photo canvas; re-running updates
  in place with no duplicates.

## 7. Decisions (owner, 2026-09-17)

1. **Canvas scale**: nominal **100 mm** width at the plane origin, height from the aspect, 60 %
   opacity, stated in the run report. No scale is ever derived from dimensions (SPEC §1).
2. **Re-import**: refresh, never duplicate — which after review B1 means parameters **upsert** by name,
   sketches are **kept** (never deleted: the user's geometry lives there), canvases are **refreshed**
   (delete + re-add, carrying the old transform). Ownership by tag, not by name alone (review S1).
3. Zip location on the Mac: any path; `~/Downloads` is merely the assumed default.
4. v1: pull `features.json` from CouchDB over HTTP (SPEC §7) and save the design into the Fusion
   project folder named by `part.path` (SPEC §8a A10) — same planner, extra executor step.

Status: reviewed by a second agent before build (see `IMPORT-SKILL-REVIEW.md`).
