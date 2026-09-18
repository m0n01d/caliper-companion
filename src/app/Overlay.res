// Overlay — canvas/export overlay palette (SPEC §8a A14b; DESIGN.md §5): the
// monochrome colours the annotate canvas (`annotate/Draw.res`) and the export
// renderer (`export/Render.res`) paint dimension lines, halos, handles and
// pills in. Both sides read the same constants module rather than each
// hard-coding literals: a canvas 2D context can't read CSS custom
// properties cheaply, and the export renderer runs off the main thread
// where `getComputedStyle` isn't available at all. `Overlay.res` lives at
// the app level (not under `annotate/`) so `Render.res` doesn't import
// "backwards" out of a sibling feature folder.
//
// Values are the DESIGN.md §2 Glass tokens by value:
//   ink    = cc-text    #F2F2F0
//   inkOn  = cc-ground   #0E0F11 (text/borders drawn *on* an ink fill or disc)
//   halo   = cc-ground at 85 %  — legibility halo under every stroke (SPEC §8a A3)
//   scrim  = cc-scrim   rgba(14,15,17,0.8) — Selected/Dimmed pill fill
//   live   = cc-live    #C9CBCE — the transient snap ring only
//   savedAlpha = 0.7 — the group alpha for a Dimmed (saved, unselected) dimension

let ink = "#F2F2F0"
let inkOn = "#0E0F11"
let halo = "rgba(14,15,17,0.85)"
let scrim = "rgba(14,15,17,0.8)"
let live = "#C9CBCE"
let savedAlpha = 0.7
