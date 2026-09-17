// SmokeTest — proves the vitest binding + compiled-ReScript pipeline works.
open Vitest

describe("toolchain", () => {
  test("ReScript test files run under vitest", () => {
    expect(1 + 1)->toBe(2)
    expect(Some(3))->toEqual(Some(3))
    expect(Belt.Result.Ok(1))->toEqual(Ok(1))
  })
})
