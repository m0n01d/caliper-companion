// Env — build-time constants that Vite's `define` substitutes (vite.config.js).
//
// `@val` on a bare identifier is a typed external, not an escape hatch: the
// compiled JS references `__CC_BASE__`, and Vite replaces that identifier with
// a string literal at build (and dev) time. Only the browser entry may use
// these; unit tests run under node where nothing defines them.

/// Served-from path with leading and trailing slash: "/" or "/caliper-companion/".
@val external base: string = "__CC_BASE__"
