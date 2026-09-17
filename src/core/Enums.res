// Enums — the on-disk / on-the-wire spellings of the four closed enums in
// Types. Shared by the JSON codec (features.json, SPEC §7) and the PouchDB doc
// mapping (SPEC §6.1) so the two can never drift.

let unitsToString = (u: Types.units) =>
  switch u {
  | Mm => "mm"
  | Inch => "in"
  }

let unitsFromString = (s: string): option<Types.units> =>
  switch s {
  | "mm" => Some(Mm)
  | "in" => Some(Inch)
  | _ => None
  }

let faceKindToString = (k: Types.faceKind) =>
  switch k {
  | Top => "top"
  | Side => "side"
  | End => "end"
  | Detail => "detail"
  }

let faceKindFromString = (s: string): option<Types.faceKind> =>
  switch s {
  | "top" => Some(Top)
  | "side" => Some(Side)
  | "end" => Some(End)
  | "detail" => Some(Detail)
  | _ => None
  }

let allFaceKinds: array<Types.faceKind> = [Top, Side, End, Detail]

let dimensionKindToString = (k: Types.dimensionKind) =>
  switch k {
  | Length => "length"
  | Diameter => "diameter"
  | Depth => "depth"
  }

let dimensionKindFromString = (s: string): option<Types.dimensionKind> =>
  switch s {
  | "length" => Some(Length)
  | "diameter" => Some(Diameter)
  | "depth" => Some(Depth)
  | _ => None
  }

let allDimensionKinds: array<Types.dimensionKind> = [Length, Diameter, Depth]

let readingSourceToString = (s: Types.readingSource) =>
  switch s {
  | Typed => "typed"
  | Wedge => "wedge"
  }

let readingSourceFromString = (s: string): option<Types.readingSource> =>
  switch s {
  | "typed" => Some(Typed)
  | "wedge" => Some(Wedge)
  | _ => None
  }
