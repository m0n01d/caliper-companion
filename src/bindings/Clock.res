// Clock — current time as ISO 8601 (SPEC.md §6: every doc's `updatedAt`,
// every dimension's `createdAt`).

let nowIso = (): string => Date.make()->Date.toISOString
