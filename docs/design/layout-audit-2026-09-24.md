# Layout audit, 2026-09-24

Owner request: "the app just needs a bit of polish, making sure the layout is consistent."
Method: every screen of `scripts/screenshot-tour.mjs` at 390 × 844 (plus Parts, Part and Annotate at
1440 × 900), with a DOM probe that recorded each block's rect, gap to the previous block, text
alignment and font. Findings are measured against DESIGN.md §11–§13. Base: `63a5522`.

"LT" = Large Title. Status: "planned" = in the polish pass on this branch (updated when it lands).

| # | Screen(s) | Element | Measured | Expected | Sev | Status |
|---|---|---|---|---|---|---|
| 1 | folders, edit, rename, picker, Part | Nav title | Centre 30 px left on folders, 36 px in Edit, 7 px right on the picker, 6 px left on Part + Edit | §11.1 "title centred" | high | planned |
| 2 | Part | Timer | Left-aligned, 13 px mono under a centred Export; centred only at ≥ 600 | §11.2 "timer centred Footnote" | high | planned |
| 3 | Part, exported | "Downloaded …" line | Left, 12 px under Export, the timer 24 px below it | §11.1 rhythm | high | planned |
| 4 | Annotate | Tool strip | Right-packed, Snap mid-strip; a bare unlabelled count; "1.00" zoom with no unit | §11.2, §7 | high | planned |
| 5 | Capture | "From library" | 195 px compact capsule; every other secondary block capsule is full width | §12.1 | high | planned |
| 6 | Annotate | "Clear" | 78 × 40 small button, left-aligned, below the fold; other Cancels are 50 px pair halves | §11.1 shape | med | planned |
| 7 | Annotate | Panel rhythm | Sections 16 px apart | §11.1 (24 / 12) | med | kept, now a stated exception (§14) |
| 8 | forms, Annotate | Label → control | 6 px | §11.1 (8) | med | planned |
| 9 | Parts | Spacing | Search → group 12, group → New Folder 12, empty line → button 20 | §11.1 (24 between sections) | med | planned |
| 10 | Folder picker | "New folder" field | Bare on the page; create and rename fields sit in a card | §11.2 | med | planned |
| 11 | Create form vs picker | Take-over chrome | Create keeps the LT and the gear; the picker puts Cancel / Done in the bar | §11.2 | med | open (a larger change) |
| 12 | Capture | Camera note | Left-aligned at x = 20 under a centred shutter | §11.1 | med | planned |
| 13 | Debug at ≥ 600 | Buttons | 512–520 px wide; New Folder caps at 400 | §12.1 | med | planned |
| 14 | Parts Edit | Toolbar text insets | 25 px from the edges; the bar's are 17 | §12.1 | low | planned |
| 15 | Annotate | Name chips | 36 px tall, 12 px text | §11.2 (40 px, 13 px) | low | planned |
| 16 | Annotate | Panel inner edge | Controls at 17 / 373, photo at 16 / 374 | §11.1 | low | planned |
| 17 | several | Empty states | Four treatments | §11.1 | low | open |
| 18 | Part vs Annotate, Settings | Group headers | "Features" hidden, "Dimensions" shown; two Settings groups unheaded | §11.2 | low | open |
| 19 | Debug | User-agent footnote | 24 px below its group at x = 16; Settings footers are 8 px below at x = 32 | §11.1 | low | planned |
| 20 | Annotate at 1440 | Side-by-side top edge | Panel 16 px below the bar, photo 24 px | §12.2 | low | planned |
| 21 | Annotate | Photo → panel gap | 12 px | §11.1 | low | kept (§14) |
| 22 | Part, Capture | Face-grid gutter | 16 px on both | — | low | consistent, no change |

Consistent already, not touched: 16 px margins on every screen; 16 px from the bar to the first
block; the 44 px bar; 50 px primary capsules, one per screen; Create | Cancel and Save | Cancel
pairs; 24 px sections on Settings, Debug and Part; identical group headers where shown; 44 px
inputs with 17 px text; the face grid; no horizontal overflow on any screen.
