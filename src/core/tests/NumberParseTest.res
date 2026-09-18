open Vitest

describe("NumberParse.parse — decimals", () => {
  test("plain integer", () => {
    expect(NumberParse.parse("42", Mm))->toEqual(Ok(42.0))
  })

  test("decimal with leading digit", () => {
    expect(NumberParse.parse("42.18", Mm))->toEqual(Ok(42.18))
  })

  test("leading dot", () => {
    expect(NumberParse.parse(".5", Mm))->toEqual(Ok(0.5))
  })

  test("trailing dot", () => {
    expect(NumberParse.parse("42.", Mm))->toEqual(Ok(42.0))
  })

  test("small decimal", () => {
    expect(NumberParse.parse("0.005", Mm))->toEqual(Ok(0.005))
  })

  test("zero is allowed", () => {
    expect(NumberParse.parse("0", Mm))->toEqual(Ok(0.0))
  })

  test("trims surrounding whitespace", () => {
    expect(NumberParse.parse("  42.18  ", Mm))->toEqual(Ok(42.18))
  })
})

describe("NumberParse.parse — inch fractions", () => {
  test("mixed fraction with a space, inch only", () => {
    expect(NumberParse.parse("1 3/8", Inch))->toEqual(Ok(1.375))
  })

  test("mixed fraction with a dash, inch only", () => {
    expect(NumberParse.parse("1-3/8", Inch))->toEqual(Ok(1.375))
  })

  test("bare fraction, inch only", () => {
    expect(NumberParse.parse("3/8", Inch))->toEqual(Ok(0.375))
  })

  test("mixed fraction in mm is a FractionNeedsInch error", () => {
    expect(NumberParse.parse("1 3/8", Mm))->toEqual(Error(NumberParse.FractionNeedsInch))
  })

  test("bare fraction in mm is a FractionNeedsInch error", () => {
    expect(NumberParse.parse("3/8", Mm))->toEqual(Error(NumberParse.FractionNeedsInch))
  })

  test("dashed mixed fraction in mm is a FractionNeedsInch error", () => {
    expect(NumberParse.parse("1-3/8", Mm))->toEqual(Error(NumberParse.FractionNeedsInch))
  })
})

describe("NumberParse.parse — errors", () => {
  test("empty is Empty", () => {
    expect(NumberParse.parse("", Mm))->toEqual(Error(NumberParse.Empty))
  })

  test("whitespace-only is Empty", () => {
    expect(NumberParse.parse("   ", Mm))->toEqual(Error(NumberParse.Empty))
  })

  test("leading minus is Negative", () => {
    expect(NumberParse.parse("-5", Mm))->toEqual(Error(NumberParse.Negative))
  })

  test("leading minus on a decimal is Negative", () => {
    expect(NumberParse.parse("-0.5", Mm))->toEqual(Error(NumberParse.Negative))
  })

  test("leading minus on an inch fraction is Negative", () => {
    expect(NumberParse.parse("-1 3/8", Inch))->toEqual(Error(NumberParse.Negative))
  })

  test("non-numeric text is Invalid", () => {
    expect(NumberParse.parse("abc", Mm))->toEqual(Error(NumberParse.Invalid))
  })

  test("zero denominator is Invalid (bare fraction)", () => {
    expect(NumberParse.parse("1/0", Mm))->toEqual(Error(NumberParse.Invalid))
    expect(NumberParse.parse("1/0", Inch))->toEqual(Error(NumberParse.Invalid))
  })

  test("zero denominator is Invalid (mixed fraction)", () => {
    expect(NumberParse.parse("1 3/0", Inch))->toEqual(Error(NumberParse.Invalid))
    expect(NumberParse.parse("1 3/0", Mm))->toEqual(Error(NumberParse.Invalid))
  })

  test("leading minus on a bare inch fraction is Negative", () => {
    expect(NumberParse.parse("-3/8", Inch))->toEqual(Error(NumberParse.Negative))
  })

  test("double dot is Invalid", () => {
    expect(NumberParse.parse("1..2", Mm))->toEqual(Error(NumberParse.Invalid))
  })

  test("comma decimal is Invalid", () => {
    expect(NumberParse.parse("1,5", Mm))->toEqual(Error(NumberParse.Invalid))
  })
})

describe("NumberParse.format / unitsLabel", () => {
  test("mm formats to 2 decimals", () => {
    expect(NumberParse.format(42.1, Mm))->toBe("42.10")
  })

  test("inch formats to 3 decimals", () => {
    expect(NumberParse.format(1.375, Inch))->toBe("1.375")
  })

  test("units labels", () => {
    expect(NumberParse.unitsLabel(Mm))->toBe("mm")
    expect(NumberParse.unitsLabel(Inch))->toBe("in")
  })
})

describe("NumberParse.fractionValue / groupInt — internal helpers", () => {
  test("fractionValue rejects a zero denominator directly", () => {
    expect(NumberParse.fractionValue(~whole=1, ~num=1, ~den=0))->toEqual(Error(NumberParse.Invalid))
  })

  test("fractionValue computes whole + num/den", () => {
    expect(NumberParse.fractionValue(~whole=1, ~num=3, ~den=8))->toEqual(Ok(1.375))
  })

  test("groupInt defaults to 0 for a missing regex group", () => {
    expect(NumberParse.groupInt([Some("3"), None], 1))->toBe(0)
  })
})

describe("NumberParse.errorMessage", () => {
  test("gives a one-line message for each error", () => {
    expect(NumberParse.errorMessage(Empty))->toBe("Enter a reading")
    expect(NumberParse.errorMessage(Negative))->toBe("Must be zero or positive")
    expect(NumberParse.errorMessage(FractionNeedsInch))->toBe("Fractions only work in inches")
    expect(NumberParse.errorMessage(Invalid))->toBe("Not a valid number")
  })
})
