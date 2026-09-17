// NumberParse — caliper-reading text parsing (SPEC §6.2/§10). Pure, no DOM.

type error = Empty | Negative | FractionNeedsInch | Invalid

// "42", "42.18", "42.", ".5" — no double dots, no thousands separators.
let decimalRe = RegExp.fromString("^(\\d+\\.\\d*|\\.\\d+|\\d+)$")
// "1 3/8" or "1-3/8".
let mixedFractionRe = RegExp.fromString("^(\\d+)[ -](\\d+)/(\\d+)$")
// "3/8".
let bareFractionRe = RegExp.fromString("^(\\d+)/(\\d+)$")

let groupInt = (result: RegExp.Result.t, index: int): int =>
  switch Array.getUnsafe(result, index) {
  | Some(s) => Float.fromString(s)->Option.getOr(0.0)->Float.toInt
  | None => 0
  }

let fractionValue = (~whole: int, ~num: int, ~den: int): result<float, error> =>
  if den == 0 {
    Error(Invalid)
  } else {
    Ok(Int.toFloat(whole) +. Int.toFloat(num) /. Int.toFloat(den))
  }

let parse = (raw: string, units: Types.units): result<float, error> => {
  let trimmed = String.trim(raw)
  if trimmed == "" {
    Error(Empty)
  } else {
    let negative = String.startsWith(trimmed, "-")
    let body = negative ? String.slice(trimmed, ~start=1) : trimmed

    if RegExp.test(decimalRe, body) {
      let value = Float.fromString(body)->Option.getOr(0.0)
      negative || value < 0.0 ? Error(Negative) : Ok(value)
    } else {
      switch RegExp.exec(mixedFractionRe, body) {
      | Some(m) =>
        let whole = groupInt(m, 1)
        let num = groupInt(m, 2)
        let den = groupInt(m, 3)
        if den == 0 {
          Error(Invalid)
        } else if units == Types.Mm {
          Error(FractionNeedsInch)
        } else if negative {
          Error(Negative)
        } else {
          fractionValue(~whole, ~num, ~den)
        }
      | None =>
        switch RegExp.exec(bareFractionRe, body) {
        | Some(m) =>
          let num = groupInt(m, 1)
          let den = groupInt(m, 2)
          if den == 0 {
            Error(Invalid)
          } else if units == Types.Mm {
            Error(FractionNeedsInch)
          } else if negative {
            Error(Negative)
          } else {
            fractionValue(~whole=0, ~num, ~den)
          }
        | None => Error(Invalid)
        }
      }
    }
  }
}

let unitsLabel = (units: Types.units): string =>
  switch units {
  | Mm => "mm"
  | Inch => "in"
  }

let format = (value: float, units: Types.units): string =>
  switch units {
  | Mm => Float.toFixed(value, ~digits=2)
  | Inch => Float.toFixed(value, ~digits=3)
  }

let errorMessage = (error: error): string =>
  switch error {
  | Empty => "Enter a reading"
  | Negative => "Must be zero or positive"
  | FractionNeedsInch => "Fractions only work in inches"
  | Invalid => "Not a valid number"
  }
