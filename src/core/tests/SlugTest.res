open Vitest

describe("Slug.make", () => {
  test("lowercases and joins words with underscores", () => {
    expect(Slug.make("Norcold freezer hinge pin"))->toBe("norcold_freezer_hinge_pin")
  })

  test("prefixes p_ when the result would start with a digit", () => {
    expect(Slug.make("2018 NB bezel"))->toBe("p_2018_nb_bezel")
  })

  test("collapses a run of non-alnum characters to one underscore", () => {
    expect(Slug.make("a---b   c!!d"))->toBe("a_b_c_d")
  })

  test("trims leading and trailing separators", () => {
    expect(Slug.make("  -- hinge pin -- "))->toBe("hinge_pin")
  })

  test("caps at 40 characters and trims a trailing underscore after capping", () => {
    let input = Array.make(~length=10, "long word")->Array.join(" ") // way over 40 chars
    let slug = Slug.make(input)
    expect(String.length(slug) <= 40)->toBeTruthy
    expect(String.endsWith(slug, "_"))->toBeFalsy
  })

  test("empty input becomes \"part\"", () => {
    expect(Slug.make(""))->toBe("part")
  })

  test("input that collapses to nothing becomes \"part\"", () => {
    expect(Slug.make("###"))->toBe("part")
  })
})
