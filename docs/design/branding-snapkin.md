# Snapkin — branding exploration (2026-09-18)

Three brand directions for the app renamed **Snapkin** (was Caliper Companion), rendered on the
Dark Sky tokens so they can be compared against the real UI before one is adopted. Nothing here is
applied: `scripts/make-icons.mjs`, `public/` and the app are untouched.

**Renders** (all in `docs/design/mockups/`): `brand-contact.png` is the one-glance sheet — A | B | C
side by side. Per direction, `brand-<slug>.html/.png` is a 1080×1350 board on ground: the icon at
1024 scaled to 360, at 180 and at 60 (squircle-masked the way iOS masks it), the wordmark on ground
and on accent, the lead tagline with the two alternates, and an in-context strip — a home-screen
tile row (Snapkin between two neutral tiles), the Parts root nav bar (with the mark as a leading
glyph where the direction wants one; the Large Title stays "Parts" in all three), the favicon at
32/16, and the A2HS hint with the icon in place of today's Share glyph.

**Method.** Every mark is pure geometry (paths, arcs, circles — no glyph fonts), drawn full-bleed on
`cc-ground` inside an 80 % safe area, so it survives any renderer and iOS's mask. Colours are
`src/theme.css` verbatim: ground `#15181D`, accent `#FF7F2A`, accent-ink `#2A1200`, live `#5AC1F2`,
text `#EEF1F5`. No direction changes a token; every text pair stays at the §6 ratios of
`palettes-2026-09-17.md` (table in §5 below). Wordmarks load one Google Font each via `<link>`
(DM Sans / Space Grotesk / Nunito). The sandbox's Chromium cannot reach fonts.googleapis.com
through the proxy, so the render injected the same woff2 files offline — the PNGs show the intended
faces; on the Mac the `<link>` loads normally. Board chrome ("Parts", "Edit", captions) is the
system stack, which in the sandbox is DejaVu Sans, not SF Pro — same as every `docs/screenshots/`
capture. The final wordmark is to be delivered as SVG paths later, not here.

## 1. The name

Snapkin is three things at once, and I want all three to stay readable:

- **snap** — snap a photo; the edge-snap that lands a tap on the part's edge; "snap to".
- **napkin** — the back-of-the-napkin sketch every engineer draws, dimensions scrawled on it.
  That sketch is what the app produces, just on a photo and exported to Fusion.
- **-kin** — a small companion, like pumpkin or munchkin; kin to the calipers and to Fusion.

## 2. Direction A — Napkin (`brand-napkin.*`, DM Sans)

**Concept.** The napkin sketch made real: a folded napkin with one dimension drawn across it. Warm
and hand-made in spirit, geometric enough to hold at 60 px.

**Mark.** A 524 px square (in the 1024 icon) tilted −6°, filled accent. Top-right corner dog-eared
(148 px cut, the flap in a light tint `#FFC59A`, the cut showing ground), bottom-left corner soft
(r 136), the other two r 56. A diagonal crease from the fold to the soft corner splits the body into
two shades (`#FF8E45` / accent) so it reads as folded cloth, not a flat sticker. Across the middle,
in ground colour at 46 px round-capped strokes: a slightly bowed dimension line (hand-drawn sag),
open chevron arrowheads, and a short extension tick at each end. Nav glyph: the same silhouette as
a 24 px 2 px-stroke outline, in `cc-text`.

**Wordmark.** `snapkin`, lowercase, DM Sans 600, −0.025 em tracking, mark leading. On accent the
napkin inverts to accent-ink with the line in accent.

**Colour.** Accent napkin on ground (7.05:1), ground line on accent (7.05:1). The flap and crease
tints are decorative only (1.1–1.7:1 against the body; never carry text). No token change.

**Taglines.** "The napkin sketch, for real." · "Measure it. Sketch it. Send it to Fusion." ·
"Dimensions on the photo, straight to CAD."

**Where it shows up.** Home-screen icon and favicon as rendered; Parts root keeps "Parts", with
the outline glyph leading in the bar (gear moves trailing, next to Edit) — optional, see risk; A2HS
hint shows the icon tile; README header = mark + wordmark on ground; export PNGs: no footer (§6).

**Risk.** At 60 px it reads as "orange document with a resize arrow" — the generic file-icon
silhouette — and a solid orange tile is the closest of the three to Fusion's own orange badge.

### 2a. Riff — lens (`brand-napkin-lens.html/.png`, 2026-09-18)

The owner picked A and asked for a camera/lens element. Five variants keep the napkin as the body
(same square, tilt, crease, dog-ear and ground-colour dimension line as §2), each rendered at
360 / 180 / 60 with a caption; then the home-screen row for the two that hold at 60 px, and the
wordmark lockup for the pick. Same rules: pure geometry, 80 % safe area, full-bleed ground, tokens
verbatim, no text pair changed.

| # | Variant | What it does | 60 px verdict |
|---|---|---|---|
| 1 | Lens corner | The flap goes; a lens ring (fold tint `#FFC59A`, ground aperture, r 132) sits half behind the cut corner. | A luggage tag at 360; at 60 a 4 px crescent and a note with a bite out of it. Napkin yes, lens no. |
| 2 | Through the lens | Accent ring r 384 / 52 px frames the napkin at 0.8 scale, line across inside. | Ring + orange square + line = a target or a record. Napkin survives; "lens" is just a circle, and the tile is the roundest, so it fights the squircle. |
| 3 | Viewfinder | Four focus brackets in `cc-text`, napkin at 0.82, base line. | Brackets shrink to four white ticks; busy, and the document-icon read of §2 stays. |
| 4 | Diameter | A lens cut into the face (ground disc r 178) with a ⌀ dimension across it in accent, tilted −30°. | Survives: orange note, dark hole, slash. Not a file icon any more — the hole breaks the "page" silhouette. Lens + measurement in one element. |
| 5 | Two-tone | 4 with the lens in `cc-live` and the ⌀ line in ground. | Survives, strongest of the five: orange note, blue lens, dark diameter — three shapes, three colours, each still separate at 60 and at 16. |
| 5-o | Two-tone, outline napkin | 5 with the napkin in ground and a 40 px accent outline (the file-icon test). | Survives (outline square + blue dot) and is not a file icon either — but it is a thinner, lighter tile than 5, and the base mark's crease/fold shading has to go. So it is the solid fill *plus the missing hole* that made §2 look like a document, not the fill alone. |

**Survive 60 px:** 4 and 5 (rendered in the home-screen row). 1 loses the lens, 2 and 3 keep the
napkin but add clutter rather than meaning.

**Pick: 5 — Two-tone.** The lens is a *diameter* dimension, which is literally one of the app's
dimension kinds, so the camera element is not decoration — it is the second thing the app measures.
Live blue on the lens follows the two-accent rule (live = the verified reading) and it is the one
change that moves the tile away from Fusion's orange badge, which was §2's risk. Colour pairs: ground
on live 8.76:1 (the ⌀ line), accent and live on ground 7.05 / 8.76, unchanged tokens. On accent the
lockup swaps the lens to `cc-live-ink` `#CDEAF7` with the line in accent-ink (a graphic, not text).
Adopting it changes the same files as §6 lists for C, with the §2a variant-5 geometry (1024-space:
the §2 napkin, disc r 178 at (512, 530), ⌀ line ±152 at −30°, 40 px strokes) halved for
`make-icons.mjs`'s 512 viewBox.

### 2b. Final (`brand-napkin-final.html/.png`, 2026-09-18)

Four ⌀-line treatments of variant 5 at 360 / 180 / 60 / 16, each with a home-screen row. (a) as is:
the −30° chevron line is the expand/fullscreen glyph at 60 and 16 and fights the 45° crease.
(b) horizontal, filled arrowheads on the rim, witness ticks: a drawing dimension, `|◀──▶|` still
reads at 60, a dark bar across a blue dot at 16. (c) −12°, ticks, lens +8 %: the bigger lens helps
at 16 but the lean drifts back toward "expand". (d) horizontal with an r 48 centre dot: an eye at
16. **Pick: (b)** — the line sits on the napkin's own axis, so it reads as drawn on it, and
ticks + filled heads are the drafting idiom, not the UI one.

**Exact geometry, 1024 × 1024 viewBox** (make-icons.mjs uses 512: halve every number, or set its
viewBox to 1024). Full-bleed `<rect>` in `cc-ground`; favicon.svg adds `rx="224"`. Everything
below inside `<g transform="rotate(-6 512 512)">`, extents 250–774 (inside the 80 % safe area):
- Napkin `M250 306Q250 250 306 250L626 250L774 398L774 718Q774 774 718 774L386 774Q250 774 250 638Z`
  fill `#FF7F2A`; crease `M250 306Q250 250 306 250L626 250L250 626Z` `#FF8E45`; flap
  `M626 250L626 398L774 398Z` `#FFC59A`; lens `<circle cx="512" cy="530" r="178">` `#5AC1F2`.
- Dimension, all `#15181D`, in `<g transform="translate(512 530)">` at 0°: line `M-122 0L122 0`
  stroke 34 round caps; arrowheads `M-174 0L-110 -28L-110 28Z` / `M174 0L110 -28L110 28Z` filled,
  stroke 10 round join (64 × 56, tips 4 px inside the rim); ticks `M-178 -46V46M178 -46V46`
  stroke 30 round caps.

## 3. Direction B — Snap (`brand-snap.*`, Space Grotesk)

**Concept.** The app's own snap feedback, frozen: the ring a snapped tap draws, landing on an edge.
Precise and technical; the mark is a diagram of what the app does.

**Mark.** A straight edge in `cc-text` (36 px stroke, y 718, x 172–852). Above it the snap ring: a
circle r 228 centred (512, 428), accent, 56 px round-capped stroke, open at the bottom (±27° around
6 o'clock). In the opening a live-blue notch — a rounded triangle, base 148 at y 596, apex at
y 692 — pointing at the edge and just touching it. Three colours, each with its app meaning: accent
= the thing you tapped, live = the verified landing, text = geometry. No nav glyph: B keeps the
bar native (gear leading, unchanged); its brand carries in the wordmark and the icon.

**Wordmark.** The name set as a dimension: `|←  snapkin  →|` — two extension lines and
outward arrowheads in accent (pure SVG geometry), the word between them as the "value" in
Space Grotesk 500, lowercase, +0.16 em tracking. On accent the whole lockup goes accent-ink.

**Colour.** Accent 7.05:1, live 8.76:1 and text 15.70:1 on ground; accent-ink on accent 7.02:1.
No token change.

**Taglines.** "Photo to parameters." · "Tap two points. Type the reading." · "Snap the edge, read
the caliper."

**Where it shows up.** Home-screen icon and favicon as rendered (the thin edge line drops out at
16 px — acceptable, the ring still reads); Parts root keeps "Parts" and its gear; A2HS hint shows
the icon tile; README header = the dimension wordmark alone, it needs no mark beside it; export
PNGs: no footer.

**Risk.** Read cold, the icon is a location pin on a line (or an abstract Q); the stroke-built mark
is the airiest of the three on the home screen, and the tracked dimension wordmark only works wide
— it cannot shrink into a nav bar or a favicon.

## 4. Direction C — Kin (`brand-kin.*`, Nunito)

**Concept.** Two caliper jaws hooked into an S: the small inside jaw in live over the large outside
jaw in accent, just open. Friendlier and rounder — a companion, and the app's two-colour rule in one
letter.

**Mark.** Two tangent circles: r 136 at (512, 352) and r 160 at (512, 648), each drawn as a 245°
arc at 96 px stroke — the top arc from −30° over the top to 85°, the bottom from −95° round to
150°. Free tips are round (a 48 px circle on each). The meeting ends are cut flat: because the
circles are tangent, the two faces come out parallel, 26 px apart — the jaw faces, open a hair.
Top arc live, bottom arc accent. Nav glyph: the same two arcs at 24 px, 2.6 px stroke, `cc-text`,
generated from the same geometry (`kinPaths` in the render script) so it never drifts.

**Wordmark.** `snapkin`, lowercase, Nunito 800, −0.015 em, mark leading. On accent the wordmark is
accent-ink; the mark goes white-over-accent-ink (a graphic, 2.52:1 — swap to mono accent-ink if that
bothers you).

**Colour.** Live 8.76:1 and accent 7.05:1 on ground; accent-ink on accent 7.02:1. No token change.

**Taglines.** "Calipers in. CAD out." · "The little tool between calipers and Fusion." · "Every
part deserves a sketch."

**Where it shows up.** Home-screen icon and favicon as rendered (the boldest of the three at 16 px);
Parts root keeps "Parts", with the S glyph leading (gear trailing) — optional; A2HS hint shows the
icon tile; README header = mark + wordmark; export PNGs: no footer.

**Risk.** An S monogram is the most common app-icon move there is, the "jaws" reading is subtle
until you are told, and at 360 the flat meeting gap can read as a broken S rather than an open one.

## 5. Contrast (WCAG, unchanged from `palettes-2026-09-17.md` §6)

| Pair | Ratio | Used by |
|---|---|---|
| text `#EEF1F5` on ground | 15.70 | wordmarks on ground; B's edge line |
| text-2 `#AFB7C1` on ground | 8.78 | board captions, tagline alternates |
| accent `#FF7F2A` on ground | 7.05 | A napkin, B ring, C outside jaw, B wordmark geometry |
| live `#5AC1F2` on ground | 8.76 | B notch, C inside jaw |
| accent-ink `#2A1200` on accent | 7.02 | every wordmark on accent |
| ground `#15181D` on accent | 7.05 | A's dimension line cut into the napkin |

Decorative-only pairs below 4.5:1 (never text): A's fold `#FFC59A` and crease `#FF8E45` on accent
(1.65 / 1.11), C's white jaw on accent in the on-accent lockup (2.52).

## 6. Recommendation

**C — Kin.** It is the only mark that is still unmistakable at 16 px (a bold two-colour S), the
split literally is the app's colour rule — live for what is verified, accent for what you touch —
and it stays clearly apart from Fusion's orange tile on the same dock, which the palette doc set as
the condition for borrowing Fusion's colours. Its rounded, chunky strokes also match the capsule /
Liquid Glass UI better than A's flat note or B's hairline diagram. A is the runner-up if the napkin
story must be *on* the icon; B's dimension wordmark is the best single wordmark idea here and can
serve as the README header in any direction without fighting the mark. Skip the nav-bar glyph
regardless: HIG puts nothing decorative in a navigation bar, and the Large Title already names the
screen. Add no footer to export PNGs: they land in Fusion as reference canvases, and a brand strip
would be traced along with the part.

**Files to adopt C.**

- `scripts/make-icons.mjs` — replace the glyph inside `svg()` with the two arcs (the 1024-space
  numbers above, halved for its 512 viewBox: circles r 68 / 80 at (256, 176) / (256, 324), stroke 48,
  tip circles r 24); keep `GROUND/ACCENT/LIVE`, `rounded` and the size loop. Then
  `node scripts/make-icons.mjs` rewrites `public/favicon.svg`, `icon-192.png`, `icon-512.png`,
  `apple-touch-icon.png` in place — `index.html` and `public/manifest.json` reference those paths
  and already say "Snapkin", so they need no edit.
- `src/app/components/A2hsHint.res` — swap `<Icon name=Share>` for the icon (`<img
  src="icon-192.png" width=28>` on a 6 px radius, or a `Mark` variant added to `Icon.res`).
- `README.md` — header image: the wordmark lockup once it exists as SVG (`docs/brand/`); until then
  link `docs/design/mockups/brand-kin.png`.
- `DESIGN.md` §11.2 — one line: the brand mark appears on the icon, the A2HS hint and the README
  only; never in the nav bar or over the canvas.
- Not touched: `Draw.res` / `Render.res` (no footer), the nav bar, the Parts Large Title.

**Overall tagline candidate:** "Calipers in. CAD out." — short, no pun to explain, and it says what
the pipeline does. ("Photo to parameters." is the precise alternative if the export's Fusion user
parameters should be the headline.)
