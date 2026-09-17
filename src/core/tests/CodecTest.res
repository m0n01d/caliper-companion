open Vitest

describe("Codec — point", () => {
  test("round-trips", () => {
    let p: Types.point = {x: 0.171, y: 0.448}
    expect(Codec.decodePoint(Codec.encodePoint(p)))->toEqual(Some(p))
  })

  test("decode rejects non-objects", () => {
    expect(Codec.decodePoint(JSON.String("nope")))->toEqual(None)
  })

  test("decode rejects an object missing a field", () => {
    let bad = JSON.Object(Dict.fromArray([("x", JSON.Number(1.0))]))
    expect(Codec.decodePoint(bad))->toEqual(None)
  })
})

describe("Codec — anchor", () => {
  test("round-trips", () => {
    let a: Types.anchor = {family: "apriltag36h11", tagId: 4, sizeMm: 20.0}
    expect(Codec.decodeAnchor(Codec.encodeAnchor(a)))->toEqual(Some(a))
  })

  test("decode rejects a non-object", () => {
    expect(Codec.decodeAnchor(JSON.String("nope")))->toEqual(None)
  })
})

describe("Codec — dimension", () => {
  test("round-trips every fixture dimension losslessly", () => {
    Array.forEach(Fixture.dimensions, (d: Types.dimension) =>
      expect(Codec.decodeDimension(Codec.encodeDimension(d)))->toEqual(Some(d))
    )
  })

  test("decode rejects an unknown kind spelling", () => {
    let json = Codec.encodeDimension(Fixture.overallL)
    let bad = switch json {
    | Object(fields) =>
      Dict.set(fields, "kind", JSON.String("not-a-kind"))
      JSON.Object(fields)
    | other => other
    }
    expect(Codec.decodeDimension(bad))->toEqual(None)
  })

  test("decode rejects a non-object", () => {
    expect(Codec.decodeDimension(JSON.Number(1.0)))->toEqual(None)
  })

  test("round-trips a Wedge-sourced dimension", () => {
    let wedge: Types.dimension = {...Fixture.overallL, source: Wedge}
    expect(Codec.decodeDimension(Codec.encodeDimension(wedge)))->toEqual(Some(wedge))
  })

  test("decode rejects an unknown source spelling", () => {
    let bad = switch Codec.encodeDimension(Fixture.overallL) {
    | Object(fields) =>
      Dict.set(fields, "source", JSON.String("carrier-pigeon"))
      JSON.Object(fields)
    | other => other
    }
    expect(Codec.decodeDimension(bad))->toEqual(None)
  })
})

describe("Codec — face", () => {
  test("round-trips a face with levelDegrees = None, outline = None", () => {
    expect(Codec.decodeFace(Codec.encodeFace(Fixture.topFace)))->toEqual(Some(Fixture.topFace))
  })

  test("round-trips a face with levelDegrees = Some(_)", () => {
    expect(Codec.decodeFace(Codec.encodeFace(Fixture.endFace)))->toEqual(Some(Fixture.endFace))
  })

  test("round-trips a face with an outline", () => {
    let withOutline: Types.face = {
      ...Fixture.topFace,
      outline: Some([{x: 0.0, y: 0.0}, {x: 1.0, y: 0.0}, {x: 1.0, y: 1.0}, {x: 0.0, y: 1.0}]),
    }
    expect(Codec.decodeFace(Codec.encodeFace(withOutline)))->toEqual(Some(withOutline))
  })

  test("round-trips a Side-kind face", () => {
    expect(Codec.decodeFace(Codec.encodeFace(Fixture.sideFace)))->toEqual(Some(Fixture.sideFace))
  })

  test("round-trips a Detail-kind face", () => {
    let detail: Types.face = {...Fixture.topFace, kind: Detail}
    expect(Codec.decodeFace(Codec.encodeFace(detail)))->toEqual(Some(detail))
  })

  test("decode rejects a non-object", () => {
    expect(Codec.decodeFace(JSON.Array([])))->toEqual(None)
  })

  test("decode rejects a wrong-typed levelDegrees", () => {
    let bad = switch Codec.encodeFace(Fixture.topFace) {
    | Object(fields) =>
      Dict.set(fields, "levelDegrees", JSON.String("bad"))
      JSON.Object(fields)
    | other => other
    }
    expect(Codec.decodeFace(bad))->toEqual(None)
  })

  test("decode rejects a wrong-typed outline", () => {
    let bad = switch Codec.encodeFace(Fixture.topFace) {
    | Object(fields) =>
      Dict.set(fields, "outline", JSON.Number(1.0))
      JSON.Object(fields)
    | other => other
    }
    expect(Codec.decodeFace(bad))->toEqual(None)
  })

  test("decode rejects an unknown kind spelling", () => {
    let bad = switch Codec.encodeFace(Fixture.topFace) {
    | Object(fields) =>
      Dict.set(fields, "kind", JSON.String("bottom"))
      JSON.Object(fields)
    | other => other
    }
    expect(Codec.decodeFace(bad))->toEqual(None)
  })
})

describe("Codec — part", () => {
  test("round-trips the fixture part losslessly", () => {
    expect(Codec.decodePart(Codec.encodePart(Fixture.part)))->toEqual(Some(Fixture.part))
  })

  test("decode rejects a missing required field", () => {
    let json = switch Codec.encodePart(Fixture.part) {
    | Object(fields) =>
      Dict.delete(fields, "slug")
      JSON.Object(fields)
    | other => other
    }
    expect(Codec.decodePart(json))->toEqual(None)
  })

  test("round-trips an Inch-units part", () => {
    let inchPart: Types.part = {...Fixture.part, units: Inch}
    expect(Codec.decodePart(Codec.encodePart(inchPart)))->toEqual(Some(inchPart))
  })

  test("decode rejects an unknown units spelling", () => {
    let bad = switch Codec.encodePart(Fixture.part) {
    | Object(fields) =>
      Dict.set(fields, "units", JSON.String("furlongs"))
      JSON.Object(fields)
    | other => other
    }
    expect(Codec.decodePart(bad))->toEqual(None)
  })

  test("decode rejects a non-object", () => {
    expect(Codec.decodePart(JSON.Null))->toEqual(None)
  })
})

// SPEC §8a A7 — `label` on face docs: additive, defaults to the kind's own
// spelling when absent so pre-A7 data keeps decoding.
describe("Codec — face label (SPEC §8a A7)", () => {
  test("encodes label alongside kind", () => {
    switch Codec.encodeFace(Fixture.sideFace) {
    | Object(fields) => expect(Dict.get(fields, "label"))->toEqual(Some(JSON.String("side")))
    | _ => expect(false)->toBeTruthy
    }
  })

  test("round-trips a custom-labelled face of a default kind", () => {
    let leftSide: Types.face = {...Fixture.sideFace, id: "face:left", label: "left_side"}
    expect(Codec.decodeFace(Codec.encodeFace(leftSide)))->toEqual(Some(leftSide))
  })

  test("a face object without label decodes with label = kind (pre-A7 data)", () => {
    let legacy = switch Codec.encodeFace(Fixture.endFace) {
    | Object(fields) =>
      Dict.delete(fields, "label")
      JSON.Object(fields)
    | other => other
    }
    expect(Codec.decodeFace(legacy))->toEqual(Some(Fixture.endFace))
  })

  test("a non-string label is treated as absent (lenient, defaults to kind)", () => {
    let bad = switch Codec.encodeFace(Fixture.topFace) {
    | Object(fields) =>
      Dict.set(fields, "label", JSON.Number(1.0))
      JSON.Object(fields)
    | other => other
    }
    expect(Codec.decodeFace(bad))->toEqual(Some(Fixture.topFace))
  })
})

describe("Codec — face required fields", () => {
  test("decode rejects a face missing any one required field", () => {
    let required = [
      "id",
      "partId",
      "kind",
      "imageAttachment",
      "pixelWidth",
      "pixelHeight",
      "levelDegrees",
      "outline",
      "capturedAt",
    ]
    Array.forEach(required, key => {
      let missing = switch Codec.encodeFace(Fixture.endFace) {
      | Object(fields) =>
        Dict.delete(fields, key)
        JSON.Object(fields)
      | other => other
      }
      expect(Codec.decodeFace(missing))->toEqual(None)
    })
  })
})
