# LOGBOOK

Newest first. One entry per working session. Record decisions, what is verified where, and what the
next session should pick up.

## 2026-09-17 — repo created, scaffold, M1 in progress (cloud sandbox, Linux)

**Environment.** Claude Code on the web, Ubuntu 24.04, Swift 6.3 installed to `/opt/swift` by hand
(the SessionStart hook now does this). No Xcode, so only `CaliperCore/` is compiled and tested here.

**Decisions.**
- TEA is a separate package target `CaliperFlow` on top of `CaliperCore` so the state machines are
  unit-tested on Linux with value comparisons. See `docs/ARCHITECTURE.md`.
- Xcode project is generated from `project.yml` with XcodeGen and not committed — a `.pbxproj`
  written blind off-Mac is a liability.
- `reconcile(_:tolerancePolicy:)`: the spec leaves the policy type as `...`; simplest reading is an
  enum `TolerancePolicy { maximum, minimum }` defaulting to `.maximum` (spec: tolerance = max).
- `features.json` uses `JSONEncoder` with `.sortedKeys` + `.prettyPrinted` + `.withoutEscapingSlashes`
  and ISO-8601 dates. Key order is therefore alphabetical, not the illustrative order in SPEC §7.
  The golden file is the canonical layout.
- M6's `telemetry` key is optional and omitted when nil so the M1 golden stays valid.
- ZIP is a hand-written STORE-only writer in `CaliperCore` (no third-party deps; `Compression`
  doesn't produce archives; the `NSFileCoordinator` upload trick is untestable off-device).

**Open questions carried from SPEC §12.** Fractional inches are parsed only when the part's units
are inch (spec M4), so the mm-only recommendation is honored by default per part; nothing to decide
in code. `detail` face plane mapping is the MCP skill's concern.
