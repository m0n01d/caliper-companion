// FeatureName — validation and naming helpers for Fusion 360 user-parameter
// names (SPEC §6.2). Pure, no DOM.

type error = Empty | TooLong | BadFormat | Reserved(string)

// Reserved list exactly as SPEC §6.2 gives it (Fusion math-function names).
let reserved = [
  "pi",
  "e",
  "sin",
  "cos",
  "tan",
  "sqrt",
  "abs",
  "floor",
  "ceil",
  "round",
  "min",
  "max",
  "log",
  "ln",
  "exp",
]

// A name that is valid apart from length: correct alphabet/first-char, any length.
let charsOnlyRe = RegExp.fromString("^[a-z][a-z0-9_]*$")
// The full, length-capped rule.
let fullRe = RegExp.fromString("^[a-z][a-z0-9_]{0,31}$")

let validate = (name: string): result<string, error> =>
  if name == "" {
    Error(Empty)
  } else if RegExp.test(fullRe, name) {
    if Array.includes(reserved, name) {
      Error(Reserved(name))
    } else {
      Ok(name)
    }
  } else if RegExp.test(charsOnlyRe, name) && String.length(name) > 32 {
    Error(TooLong)
  } else {
    Error(BadFormat)
  }

let errorMessage = (error: error): string =>
  switch error {
  | Empty => "Name can't be empty"
  | TooLong => "Too long (max 32)"
  | BadFormat => "Use a–z, 0–9 and _ ; start with a letter"
  | Reserved(name) => `\`${name}\` is reserved by Fusion`
  }

let defaults = ["overall_l", "overall_w", "overall_h", "hole_dia", "wall", "slot_w", "slot_l", "chamfer"]

// `used` (caller order, deduped) first, then `defaults` minus anything already listed.
let suggestions = (~used: array<string>): array<string> => {
  let result = []
  let addUnique = name =>
    if !Array.includes(result, name) {
      Array.push(result, name)
    }
  Array.forEach(used, addUnique)
  Array.forEach(defaults, addUnique)
  result
}
