// Ids — typed id generation (SPEC.md §6: every id is "<prefix>:" ++ uuid).

@val @scope("crypto") external uuid: unit => string = "randomUUID"

let part = (): string => "part:" ++ uuid()
let face = (): string => "face:" ++ uuid()
let dimension = (): string => "dim:" ++ uuid()
