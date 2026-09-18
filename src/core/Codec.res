// Codec — JSON encode/decode for the core doc shapes in Types.res (SPEC §6).
// This is the PouchDB-doc-body shape, distinct from the features.json export
// shape in FeaturesDocument.res (points there are [x, y] arrays, not objects).

// ---- small decode helpers -------------------------------------------------

let strField = (fields: Dict.t<JSON.t>, key: string): option<string> =>
  switch Dict.get(fields, key) {
  | Some(String(s)) => Some(s)
  | _ => None
  }

let numField = (fields: Dict.t<JSON.t>, key: string): option<float> =>
  switch Dict.get(fields, key) {
  | Some(Number(n)) => Some(n)
  | _ => None
  }

let intField = (fields: Dict.t<JSON.t>, key: string): option<int> =>
  numField(fields, key)->Option.map(Float.toInt)

let objField = (fields: Dict.t<JSON.t>, key: string): option<Dict.t<JSON.t>> =>
  switch Dict.get(fields, key) {
  | Some(Object(d)) => Some(d)
  | _ => None
  }

let arrField = (fields: Dict.t<JSON.t>, key: string): option<array<JSON.t>> =>
  switch Dict.get(fields, key) {
  | Some(Array(a)) => Some(a)
  | _ => None
  }

// An option<float> field encoded as `null` (None) or a Number (Some(n)). The
// outer option is decode success/failure; the inner one is the decoded value.
let optNumField = (fields: Dict.t<JSON.t>, key: string): option<option<float>> =>
  switch Dict.get(fields, key) {
  | Some(Null) => Some(None)
  | Some(Number(n)) => Some(Some(n))
  | _ => None
  }

// ---- point ------------------------------------------------------------

let encodePoint = (p: Types.point): JSON.t =>
  JSON.Object(Dict.fromArray([("x", JSON.Number(p.x)), ("y", JSON.Number(p.y))]))

let decodePoint = (json: JSON.t): option<Types.point> =>
  switch json {
  | Object(fields) =>
    switch (numField(fields, "x"), numField(fields, "y")) {
    | (Some(x), Some(y)) => Some({x, y})
    | _ => None
    }
  | _ => None
  }

let encodeOptPoints = (points: option<array<Types.point>>): JSON.t =>
  switch points {
  | Some(pts) => JSON.Array(Array.map(pts, encodePoint))
  | None => JSON.Null
  }

let decodeOptPoints = (fields: Dict.t<JSON.t>, key: string): option<option<array<Types.point>>> =>
  switch Dict.get(fields, key) {
  | Some(Null) => Some(None)
  | Some(Array(items)) => items->Array.map(decodePoint)->Option.all->Option.map(pts => Some(pts))
  | _ => None
  }

// ---- anchor -------------------------------------------------------------

let encodeAnchor = (a: Types.anchor): JSON.t =>
  JSON.Object(
    Dict.fromArray([
      ("family", JSON.String(a.family)),
      ("tagId", JSON.Number(Int.toFloat(a.tagId))),
      ("sizeMm", JSON.Number(a.sizeMm)),
    ]),
  )

let decodeAnchor = (json: JSON.t): option<Types.anchor> =>
  switch json {
  | Object(fields) =>
    switch (strField(fields, "family"), intField(fields, "tagId"), numField(fields, "sizeMm")) {
    | (Some(family), Some(tagId), Some(sizeMm)) => Some({family, tagId, sizeMm})
    | _ => None
    }
  | _ => None
  }

// ---- dimension ------------------------------------------------------------

let encodeDimension = (d: Types.dimension): JSON.t =>
  JSON.Object(
    Dict.fromArray([
      ("id", JSON.String(d.id)),
      ("faceId", JSON.String(d.faceId)),
      ("name", JSON.String(d.name)),
      ("kind", JSON.String(Enums.dimensionKindToString(d.kind))),
      ("value", JSON.Number(d.value)),
      ("tolerance", JSON.Number(d.tolerance)),
      ("p1", encodePoint(d.p1)),
      ("p2", encodePoint(d.p2)),
      ("source", JSON.String(Enums.readingSourceToString(d.source))),
      ("createdAt", JSON.String(d.createdAt)),
    ]),
  )

let decodeDimension = (json: JSON.t): option<Types.dimension> =>
  switch json {
  | Object(fields) =>
    switch (
      strField(fields, "id"),
      strField(fields, "faceId"),
      strField(fields, "name"),
      strField(fields, "kind")->Option.flatMap(Enums.dimensionKindFromString),
      numField(fields, "value"),
      numField(fields, "tolerance"),
      objField(fields, "p1")->Option.flatMap(f => decodePoint(Object(f))),
      objField(fields, "p2")->Option.flatMap(f => decodePoint(Object(f))),
      strField(fields, "source")->Option.flatMap(Enums.readingSourceFromString),
      strField(fields, "createdAt"),
    ) {
    | (
        Some(id),
        Some(faceId),
        Some(name),
        Some(kind),
        Some(value),
        Some(tolerance),
        Some(p1),
        Some(p2),
        Some(source),
        Some(createdAt),
      ) =>
      Some({id, faceId, name, kind, value, tolerance, p1, p2, source, createdAt})
    | _ => None
    }
  | _ => None
  }

// ---- face -------------------------------------------------------------

let encodeFace = (f: Types.face): JSON.t =>
  JSON.Object(
    Dict.fromArray([
      ("id", JSON.String(f.id)),
      ("partId", JSON.String(f.partId)),
      ("kind", JSON.String(Enums.faceKindToString(f.kind))),
      ("label", JSON.String(f.label)),
      ("imageAttachment", JSON.String(f.imageAttachment)),
      ("pixelWidth", JSON.Number(Int.toFloat(f.pixelWidth))),
      ("pixelHeight", JSON.Number(Int.toFloat(f.pixelHeight))),
      ("levelDegrees", switch f.levelDegrees {
        | Some(n) => JSON.Number(n)
        | None => JSON.Null
        }),
      ("outline", encodeOptPoints(f.outline)),
      ("capturedAt", JSON.String(f.capturedAt)),
    ]),
  )

let decodeFace = (json: JSON.t): option<Types.face> =>
  switch json {
  | Object(fields) =>
    switch (
      strField(fields, "id"),
      strField(fields, "partId"),
      strField(fields, "kind")->Option.flatMap(Enums.faceKindFromString),
      strField(fields, "imageAttachment"),
      intField(fields, "pixelWidth"),
      intField(fields, "pixelHeight"),
      optNumField(fields, "levelDegrees"),
      decodeOptPoints(fields, "outline"),
      strField(fields, "capturedAt"),
    ) {
    | (
        Some(id),
        Some(partId),
        Some(kind),
        Some(imageAttachment),
        Some(pixelWidth),
        Some(pixelHeight),
        Some(levelDegrees),
        Some(outline),
        Some(capturedAt),
      ) =>
      // SPEC §8a A7: `label` is additive. A face object written before A7
      // has none; it reads back as the default face of its kind.
      let label = strField(fields, "label")->Option.getOr(Enums.faceKindToString(kind))
      Some({
        id,
        partId,
        kind,
        label,
        imageAttachment,
        pixelWidth,
        pixelHeight,
        levelDegrees,
        outline,
        capturedAt,
      })
    | _ => None
    }
  | _ => None
  }

// ---- part -------------------------------------------------------------

let encodePart = (p: Types.part): JSON.t =>
  JSON.Object(
    Dict.fromArray([
      ("id", JSON.String(p.id)),
      ("name", JSON.String(p.name)),
      ("slug", JSON.String(p.slug)),
      ("path", JSON.String(p.path)),
      ("units", JSON.String(Enums.unitsToString(p.units))),
      ("notes", JSON.String(p.notes)),
      ("anchors", JSON.Array(Array.map(p.anchors, encodeAnchor))),
      ("createdAt", JSON.String(p.createdAt)),
      ("updatedAt", JSON.String(p.updatedAt)),
    ]),
  )

let decodePart = (json: JSON.t): option<Types.part> =>
  switch json {
  | Object(fields) =>
    switch (
      strField(fields, "id"),
      strField(fields, "name"),
      strField(fields, "slug"),
      strField(fields, "units")->Option.flatMap(Enums.unitsFromString),
      strField(fields, "notes"),
      arrField(fields, "anchors")->Option.flatMap(items => items->Array.map(decodeAnchor)->Option.all),
      strField(fields, "createdAt"),
      strField(fields, "updatedAt"),
    ) {
    | (
        Some(id),
        Some(name),
        Some(slug),
        Some(units),
        Some(notes),
        Some(anchors),
        Some(createdAt),
        Some(updatedAt),
      ) =>
      // SPEC §8a A10: `path` is additive. A part object written before A10
      // has none; it reads back at the root (the A7 `label` precedent).
      let path = strField(fields, "path")->Option.getOr("")
      Some({id, name, slug, path, units, notes, anchors, createdAt, updatedAt})
    | _ => None
    }
  | _ => None
  }
