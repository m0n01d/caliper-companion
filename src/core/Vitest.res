// Vitest — the slice of vitest's API our ReScript tests use. Tests are
// written in ReScript (SPEC §10 asks for unit tests on the compiled JS; this
// keeps the test source type-checked against the modules under test).

@module("vitest") external describe: (string, unit => unit) => unit = "describe"
@module("vitest") external test: (string, unit => unit) => unit = "test"
@module("vitest") external testAsync: (string, unit => promise<unit>) => unit = "test"

type expectation<'a>
@module("vitest") external expect: 'a => expectation<'a> = "expect"
@send external toBe: (expectation<'a>, 'a) => unit = "toBe"
@send external toEqual: (expectation<'a>, 'a) => unit = "toEqual"
@send external toBeCloseTo: (expectation<float>, float, int) => unit = "toBeCloseTo"
@send external toBeTruthy: expectation<'a> => unit = "toBeTruthy"
@send external toBeFalsy: expectation<'a> => unit = "toBeFalsy"
@send external toHaveLength: (expectation<'a>, int) => unit = "toHaveLength"
@send external toThrow: expectation<unit => 'a> => unit = "toThrow"
@get external not: expectation<'a> => expectation<'a> = "not"
