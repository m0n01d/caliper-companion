# Caliper Companion

Annotated-photo caliper capture for reverse engineering small parts. Photograph each face, tap two
edges, type the caliper reading, name the feature. Exports a dimensioned PNG per face for humans and
a `features.json` for the Fusion 360 MCP, which turns every feature into a named user parameter.

**The photo is never measured.** It is a labeled sketch. The caliper is the only source of numbers.

- Spec: [`SPEC.md`](SPEC.md) · Architecture: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) · Log: [`LOGBOOK.md`](LOGBOOK.md)
- Status: v0 dogfood MVP, one user, TestFlight target.

## Build

```sh
# Domain + Elm layer (Linux or Mac)
swift test --package-path CaliperCore

# App (Mac)
brew install xcodegen
xcodegen generate
open CaliperCompanion.xcodeproj
```
