# Caliper Companion

iOS app (Swift 6, SwiftUI, SwiftData, iOS 18) that replaces the notepad when reverse-engineering a
small part: photograph each face, tap two edges, type the caliper reading, name the feature, export
`features.json` + dimensioned PNGs for the Fusion 360 MCP. **The photo is never measured.**

```
Read SPEC.md fully before writing code. Build modules M1→M6 in order; tests first for M1, tests alongside for the rest.
Swift 6, strict concurrency, iOS 18, SwiftUI, SwiftData, zero third-party packages.
Apply the swift-best-practices skill on every file.
Do not build anything listed under Non-goals or the BLE section — the protocol seam only.
Do not change features.json shape; if the schema must change, stop and ask.
One commit per acceptance-criteria checkbox group; commit message names the module and the criteria met.
When a criterion is ambiguous, pick the simplest reading, note it in the commit body, keep going.
```

Plus the architecture addendum (SPEC.md §14): **Elm architecture everywhere** — Model / Msg /
`update` / view, effects as `Cmd` values run at the edge. `docs/ARCHITECTURE.md` is the contract:
it spells out every public type in `CaliperCore` and `CaliperFlow`. Change the doc first, then
the code.

## Layout

| Path | What | Verify with |
|------|------|-------------|
| `CaliperCore/` | Local Swift package. Target `CaliperCore` = domain (models, names, slug, reconcile, `features.json` codec, zip). Target `CaliperFlow` = TEA programs, `Store`, actors for files/export. Pure Swift, no UIKit. | `swift test --package-path CaliperCore` — runs on Linux and Mac |
| `CaliperCompanion/` | Xcode app target: SwiftUI views, SwiftData records, camera, renderer, effect handlers. | Mac only: `xcodegen generate`, open `CaliperCompanion.xcodeproj`, ⌘U |
| `CaliperCompanionTests/`, `CaliperCompanionUITests/` | App unit tests (SwiftData mapping) and the golden-path UI test. | Mac only |
| `Fixtures/hinge_pin/` | Three JPEGs + the golden `features.json`. The golden is the canonical byte layout of the export. | Byte-compared by `FeaturesDocumentTests` |
| `project.yml` | XcodeGen spec. The `.xcodeproj` is generated, not committed. | `xcodegen generate` |
| `docs/ARCHITECTURE.md` | TEA design + public API of Core and Flow. | — |
| `LOGBOOK.md` | Session log, decisions, what is verified where. Update it every session. | — |

## Bootstrapping Swift in a cloud sandbox

`.claude/hooks/session-start.sh` installs Swift 6.3 to `/opt/swift` on Claude Code on the web and
warms the package build; it is a no-op on the Mac. If hooks didn't run:

```sh
export PATH=/opt/swift/usr/bin:$PATH   # after the hook, or run the hook by hand:
CLAUDE_CODE_REMOTE=true ./.claude/hooks/session-start.sh
swift test --package-path CaliperCore
```

The app target cannot be compiled on Linux. Code under `CaliperCompanion/` written in a sandbox is
**unverified until built in Xcode** — say so in LOGBOOK.md and the PR, never claim it compiles.

## Rules of the road

- `update` functions are pure: no `UUID()`, no `Date()`, no I/O. Fresh ids and timestamps come from
  effect handlers and return as Msgs.
- `CaliperCore` and `CaliperFlow` import Foundation only. If a feature needs UIKit/SwiftUI/AVFoundation,
  it belongs in the app target behind a `Cmd`.
- Every public declaration has a one-line `///` summary (M1 criterion; keep it for Flow too).
- Zero compiler warnings in the package. Swift 6 language mode, strict concurrency complete.
- `features.json` (schema `caliper-companion/features/1`) is frozen. `telemetry` is the one optional
  key added by M6 and is omitted when nil.
- Fixture JPEGs stay small (< 100 KB each); they are sketches, not photos.

## Shared conventions

Cross-project conventions (model routing, subagent orchestration, PR screenshot rule, dev-browser)
live in the private repo `m0n01d/claude-conventions` (`CLAUDE.md` there is symlinked to
`~/code/CLAUDE.md` on the Mac). Cloud sandboxes don't see it; if you need it, add that repo to the
session and read its `CLAUDE.md`.
