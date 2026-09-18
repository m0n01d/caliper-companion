// ParametersCsv — parameters.csv writer for the export bundle (SPEC §8a
// A11). Gives a Claude-free Fusion import path via Autodesk's free
// ParameterIO add-in (Utilities → ParameterIO → Import → parameters.csv).
//
// Format verified against the add-in's own SOURCE (not just its bundled
// help file — the two disagree on one point, see below; code wins):
// https://github.com/AutodeskFusion360/ParameterIO_Python
// (`ParameterIO.bundles/Contents/ParameterIO.py`, functions
// `readParametersFromFile` / `updateParameter` (import) and
// `writeParametersToFile` (export); cloned and read directly, 2026-09-17.)
//
// Observed rules:
//  - The reader is a real `csv.reader(file, dialect=csv.excel)` — comma
//    delimiter, `"`-quoted, doublequote-escaped — not a naive
//    `str.split(',')`. Irrelevant to what we emit (we never put a comma or
//    quote in a field), but worth stating accurately rather than repeating
//    SPEC's guess at the mechanism.
//  - No header row: every row is fed straight to `updateParameter`; a
//    header row would just be parsed as a (garbage) parameter row whose
//    name is literally "name".
//  - Exactly four fields are read, in this order: `name, unit, expression,
//    comment`. `comment` is optional — a missing 4th field raises
//    `IndexError`, which is caught and treated as `''`. A 5th field, if
//    present, is never read by the importer — the add-in's own *export*
//    path writes a 5th field (`param.value`, decimal, unit-less) that its
//    *import* path ignores entirely. So our 4-field rows are exactly what
//    the reader wants, nothing more.
//  - Matching is by `name`, against `design.allParameters` collected up
//    front. New name → `design.userParameters.add(name,
//    ValueInput.createByString(expression), unit, comment)` — unit *and*
//    expression both take effect. Existing name → only `.expression` and
//    `.comment` are reassigned; `paramInModel.unit = unitOfParam` is
//    present in the source but **commented out**, so on a re-import the
//    `unit` column is parsed but never applied. (The bundled help HTML —
//    `docs/Parameter I_O.html` — claims "its unit, value and comment will
//    be updated"; the code disagrees. Code is truth, same principle as
//    CLAUDE.md's "spec data fields from the source types, not docs.") We
//    still emit `unit` on every row regardless: it's required for the
//    create path and harmless (silently ignored) on the update path.
//  - `expression` must carry the unit inline (e.g. `"42.18 mm"`): it's
//    used verbatim both as the `ValueInput.createByString` argument on
//    create and as `Parameter.expression` on update. This is exactly
//    SPEC's assumed shape.
//  - Line endings: the importer opens the file with plain `open(path)` —
//    no `newline=''` — so Python's universal-newline translation runs
//    first; CRLF, CR and LF all normalize to the same rows. Our LF-only
//    output is safe. A trailing blank line (from our required trailing
//    newline) is harmless too: `csv.reader` yields `[]` for it, and
//    `updateParameter`'s `row[0]` raises (caught, logged, skipped) rather
//    than corrupting anything.
//  - Encoding: neither `open()` call passes `encoding=`, so the add-in
//    reads/writes in the OS/locale default rather than a fixed UTF-8.
//    Every field we emit is plain ASCII except the `±`/`·` punctuation
//    inside `comment`, which could render as mojibake under a non-UTF-8
//    locale (legacy Windows). That's cosmetic only — `comment` has no
//    parsing role, and the three fields Fusion actually evaluates
//    (`name`/`unit`/`expression`) stay pure ASCII either way.
//
// Net result: SPEC's assumed shape — no header, LF, UTF-8, four fields
// `name,unit,expression,comment`, unit-qualified expression, comma-free
// fields — is confirmed correct against the source. Nothing here had to
// change shape; the one correction worth keeping in view is that the
// reader is a real CSV parser, not a naive comma split, and that "unit"
// only ever takes effect on first import, never on a re-import.

// Same number-to-string rule `features.json` uses for its `value` field:
// `Float.toString` compiles to JS's `Number.prototype.toString()`, the
// same algorithm `JSON.stringify` runs on a `JSON.Number` (see
// FeaturesDocument.res) — so `0.8`, `2`, `9`, `42.18` come out exactly as
// they do in the golden features.json, never `0.80`/`2.0`/`9.00`. Values
// reaching here are already SPEC §6.3 `round4`'d by `Reconcile.reconcile`.
let formatNumber = (n: float): string => Float.toString(n)

// A feature's `faceIds` (already deduped + sorted by id, SPEC §6.3) mapped
// to that face's label (SPEC §8a A7) for the human-readable "faces …"
// clause. Falls back to the raw id if `faces` doesn't carry that id — an
// invariant violation the caller (Export.res) never produces in practice,
// but `make`'s signature has no room for a second error case, so this
// stays total rather than partial.
let labelFor = (faces: array<Types.face>, faceId: string): string =>
  faces
  ->Array.find((f: Types.face) => f.id == faceId)
  ->Option.mapOr(faceId, (f: Types.face) => f.label)

let commentFor = (
  ~feature: Types.feature,
  ~faces: array<Types.face>,
  ~unit: string,
  ~slug: string,
): string => {
  let labels = feature.faceIds->Array.map(id => labelFor(faces, id))->Array.join(" ")
  let base =
    "±" ++
    formatNumber(feature.tolerance) ++
    " " ++
    unit ++
    " · faces " ++
    labels ++
    " · ccpart:" ++
    slug
  feature.flagged
    ? "FLAGGED spread " ++
      formatNumber(feature.spread) ++
      " > ±" ++
      formatNumber(feature.tolerance) ++
      " · " ++
      base
    : base
}

let rowFor = (
  ~feature: Types.feature,
  ~faces: array<Types.face>,
  ~unit: string,
  ~slug: string,
): string => {
  let expression = formatNumber(feature.value) ++ " " ++ unit
  let comment = commentFor(~feature, ~faces, ~unit, ~slug)
  [feature.name, unit, expression, comment]->Array.join(",")
}

let make = (
  ~part: Types.part,
  ~faces: array<Types.face>,
  ~dimensions: array<Types.dimension>,
): result<string, Reconcile.error> =>
  switch Reconcile.reconcile(dimensions) {
  | Error(err) => Error(err)
  | Ok(features) =>
    // `Reconcile.reconcile` already returns features sorted by name
    // ascending (SPEC §6.3) — the exact order FeaturesDocument.make uses
    // for `features.json`'s `features` array, so no re-sort is needed here
    // to keep the two files in lockstep.
    let unit = Enums.unitsToString(part.units)
    let rows = features->Array.map(feature => rowFor(~feature, ~faces, ~unit, ~slug=part.slug))
    Ok(rows->Array.join("\n") ++ "\n")
  }
