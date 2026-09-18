// RouteTest — SPEC §8a A13 (review S8): `Route` gets real parsing for the
// first time (`#/f/<seg>/<seg>`, one percent-encoded segment each), so it
// gets its first unit test. Tabled: `toHash → parse` round-trips, the
// shapes a hand-typed hash can take, a malformed escape, and the routes A13
// leaves alone.

open Vitest

describe("Route — folder routes (A13)", () => {
  test("toHash → parse round-trips every path the app can emit", () => {
    ["", "Miata", "Miata/Interior", "Miata (NB)/v2.1/Dwight's", "A&B+C", "Süd/Tür"]->Array.forEach(
      path => expect(Route.parse(Route.toHash(Route.Parts(path))))->toEqual(Route.Parts(path)),
    )
  })

  test("the root is #/ and each segment is percent-encoded on its own", () => {
    expect(Route.toHash(Route.Parts("")))->toBe("#/")
    expect(Route.toHash(Route.Parts("Miata")))->toBe("#/f/Miata")
    expect(Route.toHash(Route.Parts("Miata/Interior")))->toBe("#/f/Miata/Interior")
    expect(Route.toHash(Route.Parts("Miata (NB)/v2.1/Dwight's")))->toBe(
      "#/f/Miata%20(NB)/v2.1/Dwight's",
    )
    expect(Route.toHash(Route.Parts("A&B+C")))->toBe("#/f/A%26B%2BC")
    expect(Route.href(Route.Parts("Miata")))->toBe("#/f/Miata")
  })

  test("#/f, #/f/ and a trailing or doubled slash normalise", () => {
    expect(Route.parse("#/f"))->toEqual(Route.Parts(""))
    expect(Route.parse("#/f/"))->toEqual(Route.Parts(""))
    expect(Route.parse("#/f/Miata/"))->toEqual(Route.Parts("Miata"))
    expect(Route.parse("#/f/%20Miata%20//x"))->toEqual(Route.Parts("Miata/x"))
  })

  test("a malformed escape is the parts list, not a throw", () => {
    expect(Route.parse("#/f/%E0"))->toEqual(Route.Parts(""))
    expect(Route.parse("#/f/Miata/%"))->toEqual(Route.Parts(""))
  })

  test("the routes A13 leaves alone still parse", () => {
    expect(Route.parse(""))->toEqual(Route.Parts(""))
    expect(Route.parse("#"))->toEqual(Route.Parts(""))
    expect(Route.parse("#/"))->toEqual(Route.Parts(""))
    expect(Route.parse("#/parts/x"))->toEqual(Route.Part("x"))
    expect(Route.parse("#/parts/x/capture"))->toEqual(Route.Capture("x"))
    expect(Route.parse("#/parts/x/faces/y"))->toEqual(Route.Annotate("x", "y"))
    expect(Route.parse("#/settings"))->toEqual(Route.Settings)
    expect(Route.parse("#/debug"))->toEqual(Route.Debug)
    expect(Route.parse("#/nope/nope"))->toEqual(Route.Parts(""))
  })
})

// SPEC §8a A16 (review S2): the depth table decides push / pop / fade for
// every pair the UI can produce. Capture → Annotate is a push (Annotate is
// 12, not 11); same-depth sibling folders fade both ways.
describe("Route — depth and direction (A16)", () => {
  test("depth: folders by nesting, Settings 2, Debug 3, Part 10, Capture 11, Annotate 12", () => {
    expect(Route.depth(Route.Parts("")))->toBe(1)
    expect(Route.depth(Route.Parts("Miata")))->toBe(2)
    expect(Route.depth(Route.Parts("Miata/Interior")))->toBe(3)
    expect(Route.depth(Route.Settings))->toBe(2)
    expect(Route.depth(Route.Debug))->toBe(3)
    expect(Route.depth(Route.Part("x")))->toBe(10)
    expect(Route.depth(Route.Capture("x")))->toBe(11)
    expect(Route.depth(Route.Annotate("x", "y")))->toBe(12)
  })

  test("deeper is a push", () => {
    expect(Route.direction(Route.Parts(""), Route.Parts("Miata")))->toEqual(Route.Push)
    expect(Route.direction(Route.Parts("Miata"), Route.Parts("Miata/Interior")))->toEqual(
      Route.Push,
    )
    expect(Route.direction(Route.Parts(""), Route.Part("x")))->toEqual(Route.Push)
    expect(Route.direction(Route.Parts("Miata/Interior"), Route.Part("x")))->toEqual(Route.Push)
    expect(Route.direction(Route.Part("x"), Route.Capture("x")))->toEqual(Route.Push)
    expect(Route.direction(Route.Capture("x"), Route.Annotate("x", "y")))->toEqual(Route.Push)
    expect(Route.direction(Route.Part("x"), Route.Annotate("x", "y")))->toEqual(Route.Push)
    expect(Route.direction(Route.Parts(""), Route.Settings))->toEqual(Route.Push)
    expect(Route.direction(Route.Settings, Route.Debug))->toEqual(Route.Push)
  })

  test("shallower is a pop — Back from every pushed screen", () => {
    expect(Route.direction(Route.Parts("Miata"), Route.Parts("")))->toEqual(Route.Pop)
    expect(Route.direction(Route.Part("x"), Route.Parts("")))->toEqual(Route.Pop)
    expect(Route.direction(Route.Part("x"), Route.Parts("Miata/Interior")))->toEqual(Route.Pop)
    expect(Route.direction(Route.Capture("x"), Route.Part("x")))->toEqual(Route.Pop)
    expect(Route.direction(Route.Annotate("x", "y"), Route.Capture("x")))->toEqual(Route.Pop)
    expect(Route.direction(Route.Annotate("x", "y"), Route.Part("x")))->toEqual(Route.Pop)
    expect(Route.direction(Route.Settings, Route.Parts("")))->toEqual(Route.Pop)
    expect(Route.direction(Route.Debug, Route.Settings))->toEqual(Route.Pop)
    expect(Route.direction(Route.Debug, Route.Parts("")))->toEqual(Route.Pop)
  })

  test("equal depth fades, both ways", () => {
    expect(Route.direction(Route.Parts("Miata"), Route.Parts("Norcold")))->toEqual(Route.Fade)
    expect(Route.direction(Route.Parts("Norcold"), Route.Parts("Miata")))->toEqual(Route.Fade)
    expect(Route.direction(Route.Part("x"), Route.Part("y")))->toEqual(Route.Fade)
    expect(Route.direction(Route.Parts(""), Route.Parts("")))->toEqual(Route.Fade)
  })

  test("the attribute values are the three the CSS is keyed on", () => {
    expect(Route.directionAttr(Route.Push))->toBe("push")
    expect(Route.directionAttr(Route.Pop))->toBe("pop")
    expect(Route.directionAttr(Route.Fade))->toBe("fade")
  })
})
