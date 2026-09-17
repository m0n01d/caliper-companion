// FeaturesDocument — the features.json writer (SPEC §7). Frozen shape: do
// not reorder keys or change field names without a schema sign-off.

type faceExport = {face: Types.face, renderScale: float}

let schema = "caliper-companion/features/1"

// Points here are [x, y] arrays — the features.json wire form. This is
// deliberately distinct from Codec's {"x":..,"y":..} object form used for
// the PouchDB doc bodies.
let pointArray = (p: Types.point): JSON.t => JSON.Array([JSON.Number(p.x), JSON.Number(p.y)])

let encodeOptFloat = (v: option<float>): JSON.t =>
  switch v {
  | Some(n) => JSON.Number(n)
  | None => JSON.Null
  }

let encodeOptPoints = (v: option<array<Types.point>>): JSON.t =>
  switch v {
  | Some(pts) => JSON.Array(Array.map(pts, pointArray))
  | None => JSON.Null
  }

let faceKindRank = (kind: Types.faceKind): int =>
  switch kind {
  | Top => 0
  | Side => 1
  | End => 2
  | Detail => 3
  }

let encodeApp = (appVersion: string): JSON.t =>
  JSON.Object(
    Dict.fromArray([
      ("name", JSON.String("Caliper Companion")),
      ("version", JSON.String(appVersion)),
      ("runtime", JSON.String("web")),
    ]),
  )

// Anchors are reserved and always [] in v0 output, regardless of what the
// part record happens to carry (judgment call — see commit body).
let encodePart = (part: Types.part): JSON.t =>
  JSON.Object(
    Dict.fromArray([
      ("id", JSON.String(part.id)),
      ("name", JSON.String(part.name)),
      ("slug", JSON.String(part.slug)),
      // SPEC §8a A10: the folder path, right after `slug`; "" at the root.
      ("path", JSON.String(part.path)),
      ("units", JSON.String(Enums.unitsToString(part.units))),
      ("notes", JSON.String(part.notes)),
      ("anchors", JSON.Array([])),
    ]),
  )

let encodeFaceExport = (fe: faceExport): JSON.t => {
  let f = fe.face
  // SPEC §8a A7: `label` sits right after `kind` and names the bundle
  // paths. Default faces have `label == kind`, so their paths are exactly
  // the pre-A7 ones ("faces/top.jpg"); a consumer that ignores `label`
  // still works for them.
  JSON.Object(
    Dict.fromArray([
      ("id", JSON.String(f.id)),
      ("kind", JSON.String(Enums.faceKindToString(f.kind))),
      ("label", JSON.String(f.label)),
      ("image", JSON.String("faces/" ++ f.label ++ ".jpg")),
      ("annotated", JSON.String("faces/" ++ f.label ++ "_dimensioned.png")),
      ("pixelWidth", JSON.Number(Int.toFloat(f.pixelWidth))),
      ("pixelHeight", JSON.Number(Int.toFloat(f.pixelHeight))),
      ("renderScale", JSON.Number(fe.renderScale)),
      ("levelDegrees", encodeOptFloat(f.levelDegrees)),
      ("outline", encodeOptPoints(f.outline)),
    ]),
  )
}

// Measurements for one feature name: that name's dimensions, sorted by
// createdAt then faceId.
let measurementsFor = (dimensions: array<Types.dimension>, name: string): array<JSON.t> =>
  dimensions
  ->Array.filter((d: Types.dimension) => d.name == name)
  ->Array.toSorted((a: Types.dimension, b: Types.dimension) => {
    let byDate = String.compare(a.createdAt, b.createdAt)
    Ordering.isEqual(byDate) ? String.compare(a.faceId, b.faceId) : byDate
  })
  ->Array.map((d: Types.dimension) =>
    JSON.Object(
      Dict.fromArray([
        ("faceId", JSON.String(d.faceId)),
        ("value", JSON.Number(d.value)),
        ("p1", pointArray(d.p1)),
        ("p2", pointArray(d.p2)),
        ("source", JSON.String(Enums.readingSourceToString(d.source))),
        ("at", JSON.String(d.createdAt)),
      ]),
    )
  )

let encodeFeature = (dimensions: array<Types.dimension>, f: Types.feature): JSON.t =>
  JSON.Object(
    Dict.fromArray([
      ("name", JSON.String(f.name)),
      ("kind", JSON.String(Enums.dimensionKindToString(f.kind))),
      ("value", JSON.Number(f.value)),
      ("tolerance", JSON.Number(f.tolerance)),
      ("faceIds", JSON.Array(Array.map(f.faceIds, id => JSON.String(id)))),
      ("spread", JSON.Number(f.spread)),
      ("flagged", JSON.Boolean(f.flagged)),
      ("measurements", JSON.Array(measurementsFor(dimensions, f.name))),
    ]),
  )

let encodeTelemetry = (handsOnSeconds: option<int>): JSON.t =>
  JSON.Object(
    Dict.fromArray([
      (
        "handsOnSeconds",
        switch handsOnSeconds {
        | Some(n) => JSON.Number(Int.toFloat(n))
        | None => JSON.Null
        },
      ),
    ]),
  )

let make = (
  ~part: Types.part,
  ~faces: array<faceExport>,
  ~dimensions: array<Types.dimension>,
  ~exportedAt: string,
  ~appVersion: string,
  ~handsOnSeconds: option<int>,
): result<string, Reconcile.error> =>
  switch Reconcile.reconcile(dimensions) {
  | Error(err) => Error(err)
  | Ok(features) =>
    // Kind order (top, side, end, detail), then label — so two faces of the
    // same kind (SPEC §8a A7) still export deterministically.
    let sortedFaces =
      faces->Array.toSorted((a: faceExport, b: faceExport) => {
        let byKind = Int.compare(faceKindRank(a.face.kind), faceKindRank(b.face.kind))
        Ordering.isEqual(byKind) ? String.compare(a.face.label, b.face.label) : byKind
      })
    let json = JSON.Object(
      Dict.fromArray([
        ("schema", JSON.String(schema)),
        ("exportedAt", JSON.String(exportedAt)),
        ("app", encodeApp(appVersion)),
        ("part", encodePart(part)),
        ("faces", JSON.Array(Array.map(sortedFaces, encodeFaceExport))),
        ("features", JSON.Array(Array.map(features, f => encodeFeature(dimensions, f)))),
        ("telemetry", encodeTelemetry(handsOnSeconds)),
      ]),
    )
    Ok(JSON.stringify(json, ~space=2) ++ "\n")
  }
