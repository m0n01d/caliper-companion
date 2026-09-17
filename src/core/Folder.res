// Folder — the part folder path (SPEC §8a A10). Pure, no DOM.
//
// A path is "/"-separated display-name segments ("Miata/Interior"); "" is
// the root. It is a Fusion Data Panel location, not a file path (SPEC §7
// carve-out). Pages call `normalize → validate → snap` before handing a
// path to `Store.createPart(~path)` / `putPart`; Store never normalises —
// the same caller-side split as `Slug.make` / `createPart(~slug)`.

type error = BadSegment(string) | TooDeep | TooLong

let maxDepth = 6
let maxSegmentLength = 32
let maxPathLength = 120

// Any run of Unicode whitespace inside a segment collapses to one space.
let whitespaceRun = RegExp.fromString("\\s+", ~flags="g")
// One segment: a Unicode letter or digit first, then up to 31 more letters,
// digits, spaces or ` _.()&'+-`. Fusion's Data Panel takes any string; this
// keeps the set that survives a filename and a header line (review S1).
let segmentRe = RegExp.fromString("^[\\p{L}\\p{N}][\\p{L}\\p{N} _.()&'+-]{0,31}$", ~flags="u")
// "." and ".." would escape or hide inside v1's on-disk staging.
let allDots = RegExp.fromString("^\\.+$")

let normalizeSegment = (segment: string): string =>
  segment->String.trim->String.replaceRegExp(whitespaceRun, " ")

// Split on "/", trim each segment, collapse internal whitespace, drop empty
// segments, rejoin: `" /Miata//Interior /"` → `"Miata/Interior"`. Leading,
// trailing and doubled slashes are never an error (review B1).
let normalize = (input: string): string =>
  input
  ->String.split("/")
  ->Array.map(normalizeSegment)
  ->Array.filter(segment => segment != "")
  ->Array.join("/")

let segments = (path: string): array<string> => path == "" ? [] : String.split(path, "/")

let isValidSegment = (segment: string): bool =>
  RegExp.test(segmentRe, segment) && !RegExp.test(allDots, segment)

// Normalises first, so the `Ok` payload is the path to store. Checks in
// order of specificity: a bad segment names itself; then depth; then the
// whole-path cap (six 32-char segments exceed it).
let validate = (input: string): result<string, error> => {
  let path = normalize(input)
  let segs = segments(path)
  switch Array.find(segs, segment => !isValidSegment(segment)) {
  | Some(bad) => Error(BadSegment(bad))
  | None if Array.length(segs) > maxDepth => Error(TooDeep)
  | None if String.length(path) > maxPathLength => Error(TooLong)
  | None => Ok(path)
  }
}

// A path equal to an existing folder case-insensitively takes that
// folder's spelling, so `miata/interior` never opens a second section
// beside `Miata/Interior` (review S2). Grouping stays exact-string.
let snap = (path: string, ~existing: array<string>): string => {
  let lower = String.toLowerCase(path)
  switch Array.find(existing, candidate => String.toLowerCase(candidate) == lower) {
  | Some(candidate) => candidate
  | None => path
  }
}

// `"Miata/Interior/Dashboard"` → `"Miata / Interior / Dashboard"`; `""` → `""`.
let display = (path: string): string => segments(path)->Array.join(" / ")

let errorMessage = (error: error): string =>
  switch error {
  | BadSegment(segment) if String.length(segment) > maxSegmentLength =>
    `Folder name "${segment}" is too long (max ${Int.toString(maxSegmentLength)})`
  | BadSegment(segment) =>
    `Folder name "${segment}" can use letters, digits, spaces and _ . ( ) & ' + - ; start with a letter or digit`
  | TooDeep => `At most ${Int.toString(maxDepth)} folders deep`
  | TooLong => `Path too long (max ${Int.toString(maxPathLength)} characters)`
  }
