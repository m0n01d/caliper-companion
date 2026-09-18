// Slug — part slug generation (SPEC §6.2). Pure, no DOM.

// Any run of characters outside [a-z0-9] collapses to a single "_".
let nonAlnumRun = RegExp.fromString("[^a-z0-9]+", ~flags="g")
let leadingDigit = RegExp.fromString("^[0-9]")
let leadingUnderscore = RegExp.fromString("^_+")
let trailingUnderscore = RegExp.fromString("_+$")

let maxLength = 40

let make = (input: string): string => {
  let collapsed =
    input->String.toLowerCase->String.replaceRegExp(nonAlnumRun, "_")
  let trimmed =
    collapsed
    ->String.replaceRegExp(leadingUnderscore, "")
    ->String.replaceRegExp(trailingUnderscore, "")
  let prefixed = RegExp.test(leadingDigit, trimmed) ? "p_" ++ trimmed : trimmed
  let capped = String.length(prefixed) > maxLength
    ? String.slice(prefixed, ~start=0, ~end=maxLength)
    : prefixed
  let final = String.replaceRegExp(capped, trailingUnderscore, "")
  final == "" ? "part" : final
}
