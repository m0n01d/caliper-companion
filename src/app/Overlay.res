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
// Values are the DESIGN.md §2 Glass tokens by value. Since the S2 splash
// (branding-snapkin.md §9, adopted 2026-09-18) the geometry is drawn in
// Fusion's sketch blue — autodeskBlue-400 — the one hue the canvas carries:
//   ink    = cc-live    #38ABDF — lines, handles, pill text (7.36:1 on ground,
//                        5.32 / 7.11 against the halo on the pale / dark fixture)
//   inkOn  = cc-ground   #0E0F11 (text/borders drawn *on* an ink fill or disc; 7.36:1)
//   halo   = cc-ground at 85 %  — legibility halo under every stroke (SPEC §8a A3)
//   scrim  = cc-scrim   rgba(14,15,17,0.8) — Selected/Dimmed pill fill
//   live   = cc-live    #38ABDF — the transient snap ring
//   savedAlpha = 0.7 — the group alpha for a Dimmed (saved, unselected) dimension
// The 500 step (#0696D7) is a fill colour only: it measures 4.19 against the
// pale halo, too thin for a 2 px line.

let ink = "#38ABDF"
let inkOn = "#0E0F11"
let halo = "rgba(14,15,17,0.85)"
let scrim = "rgba(14,15,17,0.8)"
let live = "#38ABDF"
let savedAlpha = 0.7
