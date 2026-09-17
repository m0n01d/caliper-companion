// FolderTest — SPEC §8a A10 / docs/design/a10-folders-review.md §4's table.

open Vitest

let repeat = (s: string, n: int): string => Array.make(~length=n, s)->Array.join("")

describe("Folder.normalize", () => {
  test("root spellings all normalise to \"\"", () => {
    expect(Folder.normalize(""))->toBe("")
    expect(Folder.normalize("/"))->toBe("")
    expect(Folder.normalize("//"))->toBe("")
    expect(Folder.normalize("  "))->toBe("")
  })

  test("a single segment is unchanged", () => {
    expect(Folder.normalize("Miata"))->toBe("Miata")
  })

  test("trims segments and drops leading, trailing and doubled slashes", () => {
    expect(Folder.normalize(" /Miata//Interior /"))->toBe("Miata/Interior")
    // Review B1: `a//b` normalises, it is not an error.
    expect(Folder.normalize("a//b"))->toBe("a/b")
  })

  test("collapses internal whitespace inside a segment", () => {
    expect(Folder.normalize("Miata  Interior/Dash"))->toBe("Miata Interior/Dash")
  })

  test("keeps punctuation the alphabet allows and non-ASCII letters", () => {
    expect(Folder.normalize("Miata (NB)/v2.1/Dwight's"))->toBe("Miata (NB)/v2.1/Dwight's")
    expect(Folder.normalize("Süd/Tür"))->toBe("Süd/Tür")
  })
})

describe("Folder.validate", () => {
  test("root and normal paths are Ok with the normalised spelling", () => {
    expect(Folder.validate(""))->toEqual(Ok(""))
    expect(Folder.validate("/"))->toEqual(Ok(""))
    expect(Folder.validate("Miata"))->toEqual(Ok("Miata"))
    expect(Folder.validate(" /Miata//Interior /"))->toEqual(Ok("Miata/Interior"))
    expect(Folder.validate("Miata  Interior/Dash"))->toEqual(Ok("Miata Interior/Dash"))
    expect(Folder.validate("Miata (NB)/v2.1/Dwight's"))->toEqual(Ok("Miata (NB)/v2.1/Dwight's"))
    expect(Folder.validate("Süd/Tür"))->toEqual(Ok("Süd/Tür"))
  })

  test("a segment with a character outside the alphabet is a BadSegment", () => {
    expect(Folder.validate("a/?/b"))->toEqual(Error(Folder.BadSegment("?")))
  })

  test("a segment must start with a letter or digit", () => {
    expect(Folder.validate("-lead"))->toEqual(Error(Folder.BadSegment("-lead")))
    expect(Folder.validate(" .hidden"))->toEqual(Error(Folder.BadSegment(".hidden")))
  })

  test("an all-dots segment is a BadSegment", () => {
    expect(Folder.validate("a/../b"))->toEqual(Error(Folder.BadSegment("..")))
    expect(Folder.validate("."))->toEqual(Error(Folder.BadSegment(".")))
  })

  test("a 32-char segment is Ok; 33 is a BadSegment", () => {
    let ok = repeat("a", 32)
    let long = repeat("a", 33)
    expect(Folder.validate(ok))->toEqual(Ok(ok))
    expect(Folder.validate(long))->toEqual(Error(Folder.BadSegment(long)))
  })

  test("six segments are Ok; seven are TooDeep", () => {
    let six = Array.make(~length=6, "a")->Array.join("/")
    let seven = Array.make(~length=7, "a")->Array.join("/")
    expect(Folder.validate(six))->toEqual(Ok(six))
    expect(Folder.validate(seven))->toEqual(Error(Folder.TooDeep))
  })

  test("a path over 120 characters of valid segments is TooLong", () => {
    // 6 × 32 + 5 slashes = 197 > 120, every segment individually valid.
    let path = Array.make(~length=6, repeat("b", 32))->Array.join("/")
    expect(Folder.validate(path))->toEqual(Error(Folder.TooLong))
  })
})

describe("Folder.snap", () => {
  test("a case-insensitive match takes the existing spelling", () => {
    expect(Folder.snap("miata/INTERIOR", ~existing=["Miata/Interior"]))->toBe("Miata/Interior")
  })

  test("no match leaves the path as typed", () => {
    expect(Folder.snap("Miata/Exterior", ~existing=["Miata/Interior"]))->toBe("Miata/Exterior")
    expect(Folder.snap("", ~existing=["Miata/Interior"]))->toBe("")
  })
})

describe("Folder.display", () => {
  test("root displays as the empty string", () => {
    expect(Folder.display(""))->toBe("")
  })

  test("joins segments with \" / \"", () => {
    expect(Folder.display("a/b"))->toBe("a / b")
    expect(Folder.display("Miata/Interior/Dashboard"))->toBe("Miata / Interior / Dashboard")
  })
})

describe("Folder.errorMessage", () => {
  test("names the offending segment and the rule", () => {
    let msg = Folder.errorMessage(Folder.BadSegment("?"))
    expect(String.includes(msg, "\"?\""))->toBeTruthy
    expect(String.includes(msg, "letters"))->toBeTruthy
  })

  test("a segment over 32 chars says so rather than reciting the alphabet", () => {
    let msg = Folder.errorMessage(Folder.BadSegment(repeat("a", 33)))
    expect(String.includes(msg, "too long"))->toBeTruthy
    expect(String.includes(msg, "letters"))->toBeFalsy
  })

  test("depth and length caps quote their limits", () => {
    expect(String.includes(Folder.errorMessage(Folder.TooDeep), "6"))->toBeTruthy
    expect(String.includes(Folder.errorMessage(Folder.TooLong), "120"))->toBeTruthy
  })
})
