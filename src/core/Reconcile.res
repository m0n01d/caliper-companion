// Reconcile — pure grouping/aggregation of dimensions into features (SPEC
// §6.3). No DOM, no PouchDB.

type error = KindConflict(string)

// Round to 4dp so float-mean noise never leaks into the JSON export. Judgment
// call: applied to the `value`/`spread` fields returned to callers, not to
// the comparison used for `flagged` (that uses the raw spread — see below).
let round4 = (x: float): float => Math.round(x *. 1e4) /. 1e4

// Group dimensions by name, preserving first-seen order.
let groupByName = (dimensions: array<Types.dimension>): (
  array<string>,
  Dict.t<array<Types.dimension>>,
) => {
  let table: Dict.t<array<Types.dimension>> = Dict.make()
  let order = []
  Array.forEach(dimensions, (d: Types.dimension) => {
    switch Dict.get(table, d.name) {
    | Some(existing) => Array.push(existing, d)
    | None =>
      Array.push(order, d.name)
      Dict.set(table, d.name, [d])
    }
  })
  (order, table)
}

let conflictingNames = (order: array<string>, table: Dict.t<array<Types.dimension>>): array<
  string,
> =>
  order
  ->Array.filter(name => {
    let dims = Dict.getUnsafe(table, name)
    switch Array.get(dims, 0) {
    | None => false
    | Some(first) => !Array.every(dims, (d: Types.dimension) => d.kind == first.kind)
    }
  })
  ->Array.toSorted(String.compare)

let conflicts = (dimensions: array<Types.dimension>): array<string> => {
  let (order, table) = groupByName(dimensions)
  conflictingNames(order, table)
}

let reconcile = (dimensions: array<Types.dimension>): result<array<Types.feature>, error> => {
  let (order, table) = groupByName(dimensions)
  switch Array.get(conflictingNames(order, table), 0) {
  | Some(name) => Error(KindConflict(name))
  | None =>
    let features = Array.map(order, name => {
      let dims = Dict.getUnsafe(table, name)
      let first: Types.dimension = Array.getUnsafe(dims, 0)
      let values = Array.map(dims, (d: Types.dimension) => d.value)
      let tolerances = Array.map(dims, (d: Types.dimension) => d.tolerance)
      let mean = Array.reduce(values, 0.0, (acc, v) => acc +. v) /. Int.toFloat(Array.length(values))
      let spread = Math.maxMany(values) -. Math.minMany(values)
      let tolerance = Math.maxMany(tolerances)
      let faceIds =
        dims
        ->Array.map((d: Types.dimension) => d.faceId)
        ->Array.reduce([], (acc, id) => Array.includes(acc, id) ? acc : Array.concat(acc, [id]))
        ->Array.toSorted(String.compare)
      ({
        name,
        kind: first.kind,
        value: round4(mean),
        tolerance,
        faceIds,
        spread: round4(spread),
        flagged: spread > tolerance,
      }: Types.feature)
    })
    Ok(features->Array.toSorted((a: Types.feature, b: Types.feature) => String.compare(a.name, b.name)))
  }
}
