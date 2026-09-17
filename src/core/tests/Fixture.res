// Fixture — test-only data. A "Norcold freezer hinge pin" part: 3 faces (top,
// side, end), 9 dimensions with 9 distinct names, one measurement per name
// spread across the faces. Used by CodecTest, ReconcileTest and
// FeaturesDocumentTest (incl. the golden features.json).
//
// Not part of core/'s public surface — lives under tests/ only.

let partId = "part:00000000-0000-4000-8000-000000000001"
let topFaceId = "face:00000000-0000-4000-8000-000000000001"
let sideFaceId = "face:00000000-0000-4000-8000-000000000002"
let endFaceId = "face:00000000-0000-4000-8000-000000000003"

let part: Types.part = {
  id: partId,
  name: "Norcold freezer hinge pin",
  slug: "norcold_freezer_hinge_pin",
  units: Mm,
  notes: "",
  anchors: [],
  createdAt: "2026-09-17T13:58:00Z",
  updatedAt: "2026-09-17T14:02:09Z",
}

let topFace: Types.face = {
  id: topFaceId,
  partId,
  kind: Top,
  imageAttachment: "image.jpg",
  pixelWidth: 1600,
  pixelHeight: 1200,
  levelDegrees: None,
  outline: None,
  capturedAt: "2026-09-17T14:00:00Z",
}

let sideFace: Types.face = {
  id: sideFaceId,
  partId,
  kind: Side,
  imageAttachment: "image.jpg",
  pixelWidth: 1600,
  pixelHeight: 1200,
  levelDegrees: None,
  outline: None,
  capturedAt: "2026-09-17T14:00:30Z",
}

let endFace: Types.face = {
  id: endFaceId,
  partId,
  kind: End,
  imageAttachment: "image.jpg",
  pixelWidth: 1200,
  pixelHeight: 1600,
  levelDegrees: Some(0.4),
  outline: None,
  capturedAt: "2026-09-17T14:01:00Z",
}

let faces = [topFace, sideFace, endFace]

let point = (x, y): Types.point => {x, y}

let overallL: Types.dimension = {
  id: "dim:00000000-0000-4000-8000-000000000001",
  faceId: topFaceId,
  name: "overall_l",
  kind: Length,
  value: 42.18,
  tolerance: 0.1,
  p1: point(0.171, 0.448),
  p2: point(0.811, 0.448),
  source: Typed,
  createdAt: "2026-09-17T14:02:01Z",
}

let overallW: Types.dimension = {
  id: "dim:00000000-0000-4000-8000-000000000002",
  faceId: topFaceId,
  name: "overall_w",
  kind: Length,
  value: 12.4,
  tolerance: 0.1,
  p1: point(0.2, 0.2),
  p2: point(0.2, 0.75),
  source: Typed,
  createdAt: "2026-09-17T14:02:02Z",
}

let pinDia: Types.dimension = {
  id: "dim:00000000-0000-4000-8000-000000000003",
  faceId: topFaceId,
  name: "pin_dia",
  kind: Diameter,
  value: 6.51,
  tolerance: 0.05,
  p1: point(0.46, 0.45),
  p2: point(0.54, 0.45),
  source: Typed,
  createdAt: "2026-09-17T14:02:03Z",
}

let wall: Types.dimension = {
  id: "dim:00000000-0000-4000-8000-000000000004",
  faceId: sideFaceId,
  name: "wall",
  kind: Length,
  value: 1.8,
  tolerance: 0.05,
  p1: point(0.3, 0.3),
  p2: point(0.34, 0.3),
  source: Typed,
  createdAt: "2026-09-17T14:02:04Z",
}

let chamfer: Types.dimension = {
  id: "dim:00000000-0000-4000-8000-000000000005",
  faceId: sideFaceId,
  name: "chamfer",
  kind: Length,
  value: 0.8,
  tolerance: 0.05,
  p1: point(0.6, 0.36),
  p2: point(0.64, 0.4),
  source: Typed,
  createdAt: "2026-09-17T14:02:05Z",
}

let headDia: Types.dimension = {
  id: "dim:00000000-0000-4000-8000-000000000006",
  faceId: sideFaceId,
  name: "head_dia",
  kind: Diameter,
  value: 9.0,
  tolerance: 0.05,
  p1: point(0.4, 0.5),
  p2: point(0.6, 0.5),
  source: Typed,
  createdAt: "2026-09-17T14:02:06Z",
}

let headH: Types.dimension = {
  id: "dim:00000000-0000-4000-8000-000000000007",
  faceId: endFaceId,
  name: "head_h",
  kind: Length,
  value: 3.2,
  tolerance: 0.05,
  p1: point(0.3, 0.2),
  p2: point(0.3, 0.4),
  source: Typed,
  createdAt: "2026-09-17T14:02:07Z",
}

let grooveW: Types.dimension = {
  id: "dim:00000000-0000-4000-8000-000000000008",
  faceId: endFaceId,
  name: "groove_w",
  kind: Length,
  value: 2.0,
  tolerance: 0.05,
  p1: point(0.45, 0.55),
  p2: point(0.55, 0.55),
  source: Typed,
  createdAt: "2026-09-17T14:02:08Z",
}

let grooveDepth: Types.dimension = {
  id: "dim:00000000-0000-4000-8000-000000000009",
  faceId: endFaceId,
  name: "groove_depth",
  kind: Depth,
  value: 1.1,
  tolerance: 0.05,
  p1: point(0.5, 0.6),
  p2: point(0.5, 0.66),
  source: Typed,
  createdAt: "2026-09-17T14:02:09Z",
}

let dimensions = [overallL, overallW, pinDia, wall, chamfer, headDia, headH, grooveW, grooveDepth]

let dimensionNames = Array.map(dimensions, (d: Types.dimension) => d.name)
