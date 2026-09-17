// FolderTest — SPEC §8a A10 / docs/design/a10-folders-review.md §4's table,
// plus A12a's structure helpers, `validateSegment` and the prefix-wise `snap`.

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
    expect(Folder.snap("Miata", ~existing=[]))->toBe("Miata")
  })

  // A12a (review S4): every ancestor prefix snaps on its own, so a sibling
  // typed in another case still lands under the existing parent.
  test("prefix-wise: an ancestor prefix snaps even when the whole path is new", () => {
    expect(Folder.snap("miata/exterior", ~existing=["Miata/Interior"]))->toBe("Miata/exterior")
    expect(Folder.snap("miata/interior", ~existing=["Miata/Interior"]))->toBe("Miata/Interior")
    expect(Folder.snap("MIATA/interior/dash", ~existing=["Miata/Interior"]))->toBe(
      "Miata/Interior/dash",
    )
    expect(Folder.snap("miata", ~existing=["Miata/Interior"]))->toBe("Miata")
  })
})

describe("Folder structure helpers (A12a)", () => {
  test("parent", () => {
    expect(Folder.parent("a/b/c"))->toBe("a/b")
    expect(Folder.parent("a"))->toBe("")
    expect(Folder.parent(""))->toBe("")
  })

  test("leaf", () => {
    expect(Folder.leaf("a/b/c"))->toBe("c")
    expect(Folder.leaf("a"))->toBe("a")
    expect(Folder.leaf(""))->toBe("")
  })

  test("ancestors", () => {
    expect(Folder.ancestors("a/b/c"))->toEqual(["a", "a/b"])
    expect(Folder.ancestors("a"))->toEqual([])
    expect(Folder.ancestors(""))->toEqual([])
  })

  test("depth", () => {
    expect(Folder.depth(""))->toBe(0)
    expect(Folder.depth("a/b"))->toBe(2)
  })

  test("join", () => {
    expect(Folder.join(~parent="", ~name="a"))->toBe("a")
    expect(Folder.join(~parent="a/b", ~name="c"))->toBe("a/b/c")
  })

  test("isUnder is strict and everything is under the root", () => {
    expect(Folder.isUnder("a/b/c", ~folder="a"))->toBeTruthy
    expect(Folder.isUnder("a/b/c", ~folder="a/b"))->toBeTruthy
    expect(Folder.isUnder("ab", ~folder="a"))->toBeFalsy
    expect(Folder.isUnder("a", ~folder="a"))->toBeFalsy
    expect(Folder.isUnder("a", ~folder=""))->toBeTruthy
    expect(Folder.isUnder("", ~folder=""))->toBeTruthy
    expect(Folder.isUnder("x/y", ~folder=""))->toBeTruthy
  })

  test("rebase rewrites the prefix, the folder itself, and nothing else", () => {
    expect(Folder.rebase("a/b/c", ~from="a", ~to="z"))->toBe("z/b/c")
    expect(Folder.rebase("a", ~from="a", ~to="z"))->toBe("z")
    expect(Folder.rebase("ab/c", ~from="a", ~to="z"))->toBe("ab/c")
    expect(Folder.rebase("q", ~from="a", ~to="z"))->toBe("q")
    expect(Folder.rebase("a/b", ~from="a", ~to=""))->toBe("b")
    expect(Folder.rebase("b", ~from="", ~to="z"))->toBe("z/b")
  })
})

describe("Folder.validateSegment", () => {
  test("a valid name is Ok with its normalised spelling", () => {
    expect(Folder.validateSegment("Interior"))->toEqual(Ok("Interior"))
    expect(Folder.validateSegment(" interior "))->toEqual(Ok("interior"))
    expect(Folder.validateSegment("Miata  (NB)"))->toEqual(Ok("Miata (NB)"))
  })

  test("a slash, an empty name, a bad character and a 33-char name are BadSegment", () => {
    expect(Folder.validateSegment("a/b"))->toEqual(Error(Folder.BadSegment("a/b")))
    expect(Folder.validateSegment("?"))->toEqual(Error(Folder.BadSegment("?")))
    expect(Folder.validateSegment(""))->toEqual(Error(Folder.BadSegment("")))
    expect(Folder.validateSegment("   "))->toEqual(Error(Folder.BadSegment("")))
    let long = repeat("a", 33)
    expect(Folder.validateSegment(long))->toEqual(Error(Folder.BadSegment(long)))
  })

  test("its error renders through errorMessage like validate's", () => {
    switch Folder.validateSegment("a/b") {
    | Error(e) => expect(String.includes(Folder.errorMessage(e), "\"a/b\" can use"))->toBeTruthy
    | Ok(_) => expect(false)->toBeTruthy
    }
  })
})

describe("Folder.tree", () => {
  test("adds ancestors, dedupes, drops the root and orders depth-first", () => {
    expect(Folder.tree(["Miata/Interior", "Archive", "", "Miata/Interior"]))->toEqual([
      "Archive",
      "Miata",
      "Miata/Interior",
    ])
  })

  test("children follow their parent; siblings sort case-insensitively", () => {
    // "B"/"b" twins can't come out of `snap`, but if they did each keeps its
    // own children right under it (the exact spelling breaks the tie).
    expect(Folder.tree(["b/x", "a", "B/y", "a/Z", "a/b"]))->toEqual([
      "a",
      "a/b",
      "a/Z",
      "B",
      "B/y",
      "b",
      "b/x",
    ])
  })

  test("a parent sorts before a sibling whose name extends it", () => {
    // Segment-wise, not string-wise: "a" < "a/b" < "a b" even though "a b"
    // sorts before "a/b" as a plain string (space < slash).
    expect(Folder.tree(["a b", "a/b"]))->toEqual(["a", "a/b", "a b"])
  })

  test("empty in, empty out", () => {
    expect(Folder.tree([]))->toEqual([])
  })

  test("compareTree: a prefix sorts first from either side; equal paths are equal", () => {
    expect(Folder.compareTree("a", "a/b"))->toBe(Ordering.less)
    expect(Folder.compareTree("a/b", "a"))->toBe(Ordering.greater)
    expect(Folder.compareTree("a", "a"))->toBe(Ordering.equal)
    expect(Folder.compareTree("B", "b"))->toBe(Ordering.less)
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
