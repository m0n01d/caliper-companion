// Folder — the part folder path (SPEC §8a A10, A12a). Pure, no DOM.
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

// A12a: the path-structure helpers the picker and the store share. All of
// them treat `""` as the root and never normalise — callers hand in stored
// or already-validated paths.

// `"a/b/c"` → `"a/b"`; `"a"` → `""`; `""` → `""`.
let parent = (path: string): string => {
  let segs = segments(path)
  segs->Array.slice(~start=0, ~end=Array.length(segs) - 1)->Array.join("/")
}

// `"a/b/c"` → `"c"`; `""` → `""`.
let leaf = (path: string): string => segments(path)->Array.last->Option.getOr("")

// Every proper prefix, shallowest first: `"a/b/c"` → `["a", "a/b"]`;
// `"a"` → `[]`; `""` → `[]`.
let ancestors = (path: string): array<string> => {
  let segs = segments(path)
  Array.fromInitializer(~length=Math.Int.max(Array.length(segs) - 1, 0), i =>
    segs->Array.slice(~start=0, ~end=i + 1)->Array.join("/")
  )
}

// `Array.length(segments(path))`: `""` → 0, `"a/b"` → 2.
let depth = (path: string): int => Array.length(segments(path))

// `join(~parent="", ~name="a") = "a"`; `join(~parent="a", ~name="b") = "a/b"`.
let join = (~parent: string, ~name: string): string => parent == "" ? name : parent ++ "/" ++ name

// Strictly under: `isUnder("a/b/c", ~folder="a")` is true, `isUnder("a",
// ~folder="a")` and `isUnder("ab", ~folder="a")` are false. Everything is
// under the root.
let isUnder = (path: string, ~folder: string): bool =>
  folder == "" ? true : String.startsWith(path, folder ++ "/")

// Rewrites the `from` prefix to `to`: `rebase("a/b/c", ~from="a", ~to="z") =
// "z/b/c"`, `rebase("a", ~from="a", ~to="z") = "z"`; identity when the path
// is neither `from` nor under it. `~to=""` lifts the subtree to the root.
let rebase = (path: string, ~from: string, ~to: string): string =>
  if path == from {
    to
  } else if isUnder(path, ~folder=from) {
    let rest = from == "" ? path : String.slice(path, ~start=String.length(from) + 1)
    join(~parent=to, ~name=rest)
  } else {
    path
  }

// One segment for the picker's New Folder field (A12a, review B4):
// `normalizeSegment` first, then a `/` or nothing left is a `BadSegment`
// (`/` is the separator, so `validate` would happily accept `"a/b"` — this
// is the one place a slash is wrong), else the A10 segment rule. `validate`
// stays for whole paths.
let validateSegment = (name: string): result<string, error> => {
  let segment = normalizeSegment(name)
  if segment == "" || String.includes(segment, "/") {
    Error(BadSegment(segment))
  } else if isValidSegment(segment) {
    Ok(segment)
  } else {
    Error(BadSegment(segment))
  }
}

// Case-insensitive lookup of one exact path among `known`.
let findSpelling = (candidate: string, ~known: array<string>): option<string> => {
  let lower = String.toLowerCase(candidate)
  Array.find(known, k => String.toLowerCase(k) == lower)
}

// Prefix-wise (A12a, review S4): each ancestor prefix of `path` is snapped
// in turn against `existing` *and every ancestor of an existing path*, so
// `snap("miata/exterior", ~existing=["Miata/Interior"])` is
// `"Miata/exterior"` and `snap("miata/interior", ~existing=["Miata/Interior"])`
// is `"Miata/Interior"` — a folder never gets a case-only twin at any level.
// Grouping stays exact-string; A10's whole-path cases still hold.
let snap = (path: string, ~existing: array<string>): string => {
  let known = existing->Array.flatMap(e => Array.concat(ancestors(e), [e]))
  segments(path)->Array.reduce("", (acc, segment) => {
    let candidate = join(~parent=acc, ~name=segment)
    findSpelling(candidate, ~known)->Option.getOr(candidate)
  })
}

// Segment-wise, case-insensitive: a parent sorts right before its children,
// siblings alphabetically. Two spellings that differ only in case (kept
// apart by `snap`, so never expected) break the tie on that segment's exact
// spelling, so even a twin keeps its children directly under it.
let compareTree = (a: string, b: string): Ordering.t => {
  let sa = segments(a)
  let sb = segments(b)
  let rec go = (i: int): Ordering.t =>
    switch (sa[i], sb[i]) {
    | (None, None) => Ordering.equal
    | (None, Some(_)) => Ordering.less
    | (Some(_), None) => Ordering.greater
    | (Some(x), Some(y)) =>
      let c = String.compare(String.toLowerCase(x), String.toLowerCase(y))
      let c = c == Ordering.equal ? String.compare(x, y) : c
      c == Ordering.equal ? go(i + 1) : c
    }
  go(0)
}

// The picker's flat tree (A12a): `paths` ∪ every ancestor, deduplicated,
// root excluded, ordered depth-first so children follow their parent and
// siblings sort case-insensitively. `["Miata/Interior", "Archive"]` →
// `["Archive", "Miata", "Miata/Interior"]`.
let tree = (paths: array<string>): array<string> => {
  let all = paths->Array.flatMap(p => Array.concat(ancestors(p), [p]))->Array.filter(p => p != "")
  let seen = []
  all->Array.forEach(p =>
    if !Array.includes(seen, p) {
      Array.push(seen, p)
    }
  )
  seen->Array.toSorted(compareTree)
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
