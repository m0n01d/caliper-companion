# Caliper Companion — Linked Mode spec (v1)

**Depends on:** accounts + CouchDB sync (v1). **Extends:** `SPEC.md` (web v0). Keep this short; the data-model split is the whole design.

## 1. What it is

One part, two devices, live. The phone owns geometry (photos, taps). The desktop owns readings (caliper value, name, kind, tolerance) because it has a real keyboard and it's where Fusion runs. Neither device edits the other's documents, so sync never conflicts. Single-device mode keeps working unchanged; linked mode is an overlay, not a replacement.

## 2. Data model changes

```rescript
// Existing dimension doc gains a status. Phone writes it; desktop only reads it.
type dimension = { ...existing, status: Pending | Saved }

// New. Desktop writes it. One per dimension. This is where value/name/kind/tol now live.
type reading = {
  id: string,            // "reading:" ++ dimensionId  — deterministic, one per dimension
  partId: string,
  dimensionId: string,
  value: float, name: string, kind: dimensionKind, tolerance: float,
  source: Typed | Wedge,
  deviceId: string, at: string,
}

// New. Whichever device acted last writes it. One per part.
type session = {
  id: string,            // "session:" ++ partId
  partId: string,
  activeFaceId: option<string>,
  pendingDimensionId: option<string>,   // the one the desktop should focus
  phoneDeviceId: option<string>, desktopDeviceId: option<string>,
  updatedAt: string,
}
```

- Migration for v0 data: `dimension.value/name/kind/tolerance` move into a `reading` doc keyed by the dimension id. `Feature` derivation joins `dimension × reading`; a dimension with no reading is Pending.
- `_id` of a reading is derived from the dimension id, so a retry can't create duplicates.
- Ownership rule (enforced in `store/`, tested): phone role never writes `reading`; desktop role never writes `dimension` geometry or `face`. Either may write `session`.

## 3. Roles and handoff

- A device declares its role once per part: `phone` (has camera, touch) or `desktop` (has keyboard). A phone can still take the desktop role if no desktop is present — that's single-device mode.
- Handoff: desktop shows a QR encoding `{partId, faceId, sessionToken}`; the phone scans it and opens that face signed in. No account entry at the bench.

## 4. The loop

1. Phone: tap p1, tap p2 → write `dimension {status: Pending}` and `session.pendingDimensionId`.
2. Sync (CouchDB live, target < 500 ms on wifi).
3. Desktop: queue card lights for `pendingDimensionId`; reading field takes focus automatically.
4. Dongle types `42.18⏎` (or user types) → focus moves to name → Enter saves → write `reading`; phone-side overlay turns solid when the reading doc arrives.
5. Desktop clears `session.pendingDimensionId`, or sets it to the next Pending dimension in creation order.
6. Phone never blocks: additional taps create more Pending dimensions; desktop drains them FIFO.
7. Optional: the Fusion MCP skill follows the part's `_changes` feed and upserts a user parameter per reading as it lands.

## 5. Desktop layout

Three columns at ≥ 1024 px: faces (left, 260), canvas mirror (center, read-only), queue + saved table (right, 340). Below 1024 px it's the phone layout with the desktop role. Canvas mirror shows the pending dimension in amber with the live value as it's typed (from a transient `session.draftValue`, optional).

## 6. Fallbacks

- Phone "Enter here instead": phone takes the desktop role for that dimension only; writes the `reading` itself. Allowed because the desktop never wrote one.
- Desktop offline: phone keeps creating Pending dimensions; queue drains when it reconnects.
- No wifi at the bench: single-device mode. Linked mode requires both devices to reach CouchDB.

## 7. Acceptance criteria

- [ ] Given phone and desktop on the same part, when the phone drops p2, then within 1 s the desktop's reading field has focus for that dimension (Playwright with two contexts and a local CouchDB).
- [ ] Given three Pending dimensions created in order A, B, C, when the desktop saves A, then focus moves to B, then C; never out of order.
- [ ] Given both devices write within the same second, then no PouchDB conflict documents exist after sync (assert `_conflicts` empty for every doc in the part).
- [ ] Given a `reading` write is retried, then exactly one reading doc exists for that dimension.
- [ ] Given the phone taps "Enter here instead" and saves, then the desktop's queue drops that dimension within 1 s and shows it in Saved.
- [ ] Given the desktop goes offline for 60 s while the phone creates 5 dimensions, when it reconnects, then all 5 appear in the queue in order.
- [ ] Given a v0 part (values on dimension docs), when the app migrates, then every dimension has a matching reading and `Feature` output is byte-identical to pre-migration.
- [ ] Given a QR scan, then the phone opens that part and face signed in, with no typing.

## 8. Non-goals

- Two phones, or two desktops, on one part (later: multi-user shop mode).
- Real-time cursor sharing beyond `pendingDimensionId`.
- Any Bluetooth code. The dongle is a keyboard; the app's focus order is the integration.
