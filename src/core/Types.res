// Types — the v0 data model, verbatim from SPEC.md §6.
//
// Pure ReScript, no DOM. Frozen: the JSON contract (§7) and the PouchDB doc
// shapes (§6.1) are derived from these, so a change here is a schema change
// and needs sign-off. Derived types (`feature`) are never stored.

type units = Mm | Inch
type faceKind = Top | Side | End | Detail
type dimensionKind = Length | Diameter | Depth

/// Wedge = a keyboard-wedge dongle typed it. Indistinguishable at runtime;
/// set by a user toggle (SPEC M4).
type readingSource = Typed | Wedge

/// 0.0–1.0 of the *oriented* image width/height (EXIF rotation applied at decode).
type point = {x: float, y: float}

type dimension = {
  id: string, // "dim:" ++ uuid
  faceId: string,
  name: string, // validated by FeatureName
  kind: dimensionKind,
  value: float, // part units
  tolerance: float, // ± part units
  p1: point,
  p2: point,
  source: readingSource,
  createdAt: string, // ISO 8601
}

type face = {
  id: string, // "face:" ++ uuid
  partId: string,
  // `kind` is the sketch-plane hint Fusion needs (top→XY, side→XZ, end→YZ,
  // detail→XY); `label` is the face's unique-per-part slug (same rule as
  // feature names, SPEC §6.2). For the four default faces
  // `label == Enums.faceKindToString(kind)`, so their export paths are
  // unchanged; a custom face ("left_side", kind Side) gets its own paths.
  // SPEC §8a A7 — additive schema delta, owner-approved.
  kind: faceKind,
  label: string,
  imageAttachment: string, // attachment name on this doc, e.g. "image.jpg"
  pixelWidth: int,
  pixelHeight: int, // oriented dimensions
  levelDegrees: option<float>,
  outline: option<array<point>>, // optional 4 corners, reserved for future AR review; no v0 UI
  capturedAt: string,
}

/// Reserved for AR review. Always [] in v0.
type anchor = {family: string, tagId: int, sizeMm: float}

type part = {
  id: string, // "part:" ++ uuid
  name: string,
  slug: string,
  units: units,
  notes: string,
  anchors: array<anchor>, // reserved, always [] in v0
  createdAt: string,
  updatedAt: string,
}

/// Derived, never stored. Produced by `Reconcile.reconcile`.
type feature = {
  name: string,
  kind: dimensionKind,
  value: float, // reconciled (mean)
  tolerance: float, // max of contributors
  faceIds: array<string>,
  spread: float, // max − min
  flagged: bool, // spread > tolerance
}
