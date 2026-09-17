open Vitest

describe("FeatureName.validate", () => {
  test("accepts overall_l", () => {
    expect(FeatureName.validate("overall_l"))->toEqual(Ok("overall_l"))
  })

  test("accepts hole_dia2", () => {
    expect(FeatureName.validate("hole_dia2"))->toEqual(Ok("hole_dia2"))
  })

  test("rejects Overall_L (uppercase)", () => {
    expect(FeatureName.validate("Overall_L"))->toEqual(Error(FeatureName.BadFormat))
  })

  test("rejects 2nd_hole (starts with a digit)", () => {
    expect(FeatureName.validate("2nd_hole"))->toEqual(Error(FeatureName.BadFormat))
  })

  test("rejects pi (reserved)", () => {
    expect(FeatureName.validate("pi"))->toEqual(Error(FeatureName.Reserved("pi")))
  })

  test("rejects sqrt (reserved)", () => {
    expect(FeatureName.validate("sqrt"))->toEqual(Error(FeatureName.Reserved("sqrt")))
  })

  test("rejects every reserved word", () => {
    Array.forEach(FeatureName.reserved, name =>
      expect(FeatureName.validate(name))->toEqual(Error(FeatureName.Reserved(name)))
    )
  })

  test("rejects a 33-char name as TooLong", () => {
    let name = "a" ++ String.repeat("b", 32) // 33 chars, otherwise valid
    expect(String.length(name))->toBe(33)
    expect(FeatureName.validate(name))->toEqual(Error(FeatureName.TooLong))
  })

  test("accepts a 32-char name (boundary)", () => {
    let name = "a" ++ String.repeat("b", 31) // 32 chars
    expect(String.length(name))->toBe(32)
    expect(FeatureName.validate(name))->toEqual(Ok(name))
  })

  test("rejects empty", () => {
    expect(FeatureName.validate(""))->toEqual(Error(FeatureName.Empty))
  })
})

describe("FeatureName.errorMessage", () => {
  test("gives a one-line message for each error", () => {
    expect(FeatureName.errorMessage(Empty))->toBe("Name can't be empty")
    expect(FeatureName.errorMessage(TooLong))->toBe("Too long (max 32)")
    expect(FeatureName.errorMessage(BadFormat))->toBe("Use a–z, 0–9 and _ ; start with a letter")
    expect(FeatureName.errorMessage(Reserved("pi")))->toBe("`pi` is reserved by Fusion")
  })
})

describe("FeatureName.suggestions", () => {
  test("used names come first, in caller order, deduped", () => {
    expect(FeatureName.suggestions(~used=["wall", "wall", "hole_dia"]))->toEqual([
      "wall",
      "hole_dia",
      "overall_l",
      "overall_w",
      "overall_h",
      "slot_w",
      "slot_l",
      "chamfer",
    ])
  })

  test("defaults minus anything already listed, when nothing used", () => {
    expect(FeatureName.suggestions(~used=[]))->toEqual(FeatureName.defaults)
  })

  test("all-defaults used yields no duplicates", () => {
    expect(FeatureName.suggestions(~used=FeatureName.defaults))->toEqual(FeatureName.defaults)
  })
})
