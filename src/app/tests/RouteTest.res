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
