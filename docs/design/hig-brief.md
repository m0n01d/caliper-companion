# Apple HIG brief — Caliper Companion

Scope: everything in the Apple Human Interface Guidelines *except* Liquid Glass material mechanics
(a sibling brief, `liquid-glass-web.md`, covers that). This doc is numbers-first and screen-by-screen,
aimed at making Caliper Companion feel native on iPhone without becoming a native app.

**Method note.** `developer.apple.com/design/human-interface-guidelines/*` is a client-rendered app;
a plain fetch returns only the page title. Every citation below was pulled from the same JSON the
page itself loads (`developer.apple.com/tutorials/data/design/human-interface-guidelines/<slug>.json`),
which is the real, current HIG content, not a cache or paraphrase — quotes are close paraphrase of
that JSON's text nodes. Two consequences worth flagging up front:
- Apple's 2023+ HIG rewrite dropped most fixed pt values from prose (margins, bar heights, corner
  radii). Where a number below isn't in the current HIG text, it's marked **[secondary]** and sourced
  separately — still real, just not from Apple's current copy.
- In the June 2025 rewrite, standalone **Navigation bars** and **Touchscreen gestures** pages were
  folded into **Toolbars** and **Gestures** respectively (confirmed by each page's change log). There
  is no dedicated "Technologies → Web" HIG page for web apps/PWAs — the closest, **Web views**, is
  about embedding `WKWebView` in a native app, not about building one; noted where relevant instead
  of forced-fit.

---

## 1. Numbers that bind

### Tap targets and spacing
| Value | Number | Source |
|---|---|---|
| Default control size, iOS/iPadOS | **44×44 pt** | Accessibility → Mobility table [1] |
| Minimum control size, iOS/iPadOS | 28×28 pt (Apple's own floor, not a target — treat 44 as the real minimum for this app) | Accessibility [1] |
| Button hit region, general rule | "at least 44×44 pt" | Buttons [2] |
| Padding around bezeled controls | ~12 pt | Accessibility [1] |
| Padding around non-bezeled controls | ~24 pt | Accessibility [1] |
| System page margin (iPhone) | 16 pt (390 pt-wide devices), 20 pt on some larger/Plus widths | **[secondary]** — not stated in current HIG prose; from Apple's iOS Design Resources templates, stable since iOS 7 | Apple Design Resources [3] |
| Nav bar height, compact | 44 pt | **[secondary]** — `UINavigationBar` default; not restated in current prose | Long-standing UIKit default [4] |
| Nav bar height, large title expanded | ~96 pt (44 + ~52 for the title row) | **[secondary]**, same caveat | [4] |

DESIGN.md already uses 44 px as its tap floor and 20 px page padding — both land inside HIG's real
numbers. No change needed there.

### Text styles (iOS/iPadOS, Dynamic Type "Large" — the default size)
Pulled straight from Typography → Specifications → "iOS, iPadOS Dynamic Type sizes" → **Large (default)**
tab [5]. DESIGN.md's numbers match this table exactly — confirmed, not just close:

| Style | Weight | Size (pt) | Leading (pt) | Emphasized weight |
|---|---|---|---|---|
| Large Title | Regular | 34 | 41 | Bold |
| Title 1 | Regular | 28 | 34 | Bold |
| Title 2 | Regular | 22 | 28 | Bold |
| Title 3 | Regular | 20 | 25 | Semibold |
| Headline | Semibold | 17 | 22 | Semibold |
| Body | Regular | 17 | 22 | Semibold |
| Callout | Regular | 16 | 21 | Semibold |
| Subhead | Regular | 15 | 20 | Semibold |
| Footnote | Regular | 13 | 18 | Semibold |
| Caption 1 | Regular | 12 | 16 | Semibold |
| Caption 2 | Regular | 11 | 13 | Semibold |

This is one Dynamic Type step among many (xSmall…xxxLarge, then AX1–AX5 for accessibility sizes) —
each text element scales through the *entire* table as the user changes their text-size setting, not
just at this one row. Default/minimum custom type size for iOS is **17 pt default / 11 pt minimum** [1][5].

### Dynamic Type — what "supporting" it actually requires
- Use the real text-style stack, not fixed px, so text scales through xSmall → xxxLarge → AX1–AX5.
  AX5 Large Title is 60 pt/70 leading — layouts must survive that without clipping [5].
- On the web: `-apple-system-body` isn't a real CSS keyword — WebKit doesn't expose Dynamic Type to
  CSS at all. The honest web equivalent is respecting the user's **Text Size** setting via `rem` off
  the root font-size *if* you also handle iOS Safari's separate page-zoom/text-size controls, or —
  more realistically for a PWA — just make sure nothing breaks under 120–150% browser zoom (SPEC.md's
  own "Edge cases" §8 already requires this). Full Dynamic Type parity isn't achievable in Safari web
  content; don't promise it.

### Contrast minimums
| Text size / weight | Minimum ratio |
|---|---|
| Up to 17 pt, any weight | **4.5:1** |
| 18 pt and up, any weight | 3:1 |
| Bold, any size | 3:1 |

Source: Accessibility → Vision, which cites this as the table Accessibility Inspector itself uses,
built on WCAG AA [1]. Note this is looser than strict WCAG (which requires *both* ≥18pt/≥14pt-bold
*and* the size threshold — Apple's "bold at any size" rule is a simplification, not a WCAG quote).
Dark Mode adds a stronger recommendation: **4.5:1 minimum, but "strive for 7:1" for custom
foreground/background pairs, especially small text** [6]. DESIGN.md's own contrast table (`cc-text-2`
at 8.7:1/7:1, `cc-text-3` at ≥4.6:1) already clears both bars.

### Colour semantics
- System label colors: **label / secondaryLabel / tertiaryLabel / quaternaryLabel**, used to convey
  relative importance (primary info / subheading-supplemental / unavailable-item text / watermark) [7].
- Current HIG prose does **not** publish exact opacity percentages for these (that used to be in
  older PDFs). The well-known values — **[secondary]**, from UIKit's shipped `UIColor` behavior,
  still accurate — are approximately: label 100%, secondaryLabel ~60%, tertiaryLabel ~30%,
  quaternaryLabel ~18% in light mode; dark mode uses different (slightly higher-opacity) numbers for
  the same visual weight. Don't hand-pick percentages from memory in code — derive them from
  DESIGN.md's own `cc-text` / `cc-text-2` / `cc-text-3` tokens, which already encode the right
  *relationships* even if the absolute hex differs from system gray.
- Backgrounds: iOS defines two parallel sets — **system** (`systemBackground` /
  `secondarySystemBackground` / `tertiarySystemBackground`) for plain content, and **grouped**
  (`systemGroupedBackground` / …) for grouped table/list views — plus, in Dark Mode specifically, a
  **base vs elevated** pair per background level so a foreground sheet/popover can read as "above"
  its parent [6][8]. Caliper Companion's Part screen (a grouped list of faces + features) is exactly
  the grouped-background use case.
- Separators: `separator` (lets content show through) vs `opaqueSeparator` (fully opaque) [8].
- One accent colour per app is the norm: "keep the number of prominent [colored] buttons to one or
  two per view" [2]; "apply color sparingly… reserve it for elements that truly benefit from
  emphasis" [9]. See §3 for how this maps onto amber/teal.

### Corner radii
HIG no longer publishes fixed radius numbers for general UI; the operative concept is **concentric
corners** — a control's corner radius should nest visually inside its container's, matching curvature
rather than using an arbitrary value (stated for toolbar-hosted controls and for app icons matching
the device bezel) [7][10][11]. DESIGN.md's radius scale (10 / 12 / 14 / 16 px) is consistent with this
principle — small-to-large nesting — even though none of those numbers come from an HIG table.

### Safe areas and layout guides
- A **safe area** is the region not covered by hardware features or system chrome (status bar,
  Dynamic Island, home indicator, bars); respecting it is required so system UI doesn't obstruct
  content [12].
- **Size classes** (compact/regular × horizontal/vertical), not device type or orientation, are what
  layout decisions should key off — irrelevant for this phone-portrait-only app, but worth knowing
  the vocabulary if Dwight ever asks about iPad [12].
- On the web: `env(safe-area-inset-*)`, `100dvh`, no `position: fixed` bars over content that
  resizes with the keyboard — all already in DESIGN.md/SPEC.md and consistent with the HIG's safe-area
  intent, just implemented at the CSS layer instead of via `UILayoutGuide` [12].

Sources: [1] developer.apple.com/design/human-interface-guidelines/accessibility · [2]
.../buttons · [3] developer.apple.com/design/resources/ (Apple's design templates, not the HIG text
itself) · [4] longstanding `UINavigationBar` default height, widely documented in Apple's own
sample code and dev-forum threads; not restated in current HIG copy · [5] .../typography · [6]
.../dark-mode · [7] .../color · [8] .../labels · [9] .../materials · [10] .../toolbars · [11]
.../app-icons · [12] .../layout

---

## 2. Component-by-component guidance, mapped to this app's screens

### Parts list
| HIG says | On the web this means… |
|---|---|
| Prefer a list/table for scannable text rows; grouped style separates sections with headers/footers/spacing [13] | Grouped-list visual treatment (DESIGN.md's `cc-surface` rows on `cc-ground`) already matches; keep rows text-forward, image optional |
| Provide feedback on selection appropriate to what happens — persistent highlight for navigation, brief highlight + checkmark for state toggles [13] | Tapping a part row navigates (no toggle state), so a brief pressed-state is enough — no persistent "selected" styling needed on return |
| A **large title** belongs at the root of a navigation hierarchy and shrinks to a standard title on scroll [10] | Parts list is root — this is the one screen that should use `cc-font-display` 30px sized text acting as a large title; every pushed screen below it gets a small title only, per HIG's own hierarchy signal |

### Part screen (faces row, features table, Export, timer)
| HIG says | On the web this means… |
|---|---|
| Back button = standard chevron symbol, no "Back" text label — don't reinvent it [10] | `‹` icon-only button, `aria-label="Back"`, no visible text — DESIGN.md's spec already says icon-only; this confirms it's not just a shop-UI stylistic choice, it's the platform convention |
| Multicolumn table: use noun/short-noun-phrase column headings, no ending punctuation [13] | Features table headers ("NAME", "VALUE", "TOL", "FACE") — already matches |
| Table can support select/reorder; iOS requires an explicit edit mode before selecting rows [13] | Not needed here — no reordering in v0 |
| Keep the number of prominent (colored) buttons to one or two per view [2] | Export is the one prominent amber button on this screen — correct; don't also tint "Add dimension" |
| Progress indicators: prefer determinate over indeterminate when duration is knowable [14] | The hands-on timer is a stopwatch display, not a progress bar — no HIG progress-indicator component applies; it's just a `Label`/mono text readout, which is the right call |

### Capture screen (four face kinds, camera/library file inputs, recapture dialog)
| HIG says | On the web this means… |
|---|---|
| Segmented control: aim for ≤5 segments on iPhone [15] | 4 face kinds (Top/Side/End/Detail) is safely under the limit |
| Destructive-consequence action that isn't the user's deliberate intent should get a confirming alert; recapturing discards dimensions unless "keep" is chosen — that's exactly this case [16] | Recapture confirmation should be a native-feeling **alert** (title + 2 buttons: destructive "Replace" / "Cancel"), not a full action sheet — HIG reserves action sheets for offering *choices about an intentional action*, alerts for *confirming consequences of one* [16][17]. This dialog is closer to an alert |
| Alerts: destructive style on the button that performs an action the person **didn't** deliberately choose; default button goes trailing/top, Cancel leading/bottom [16] | "Replace" gets destructive (red/error) styling, sits trailing; "Cancel" is not the default focus target |

### Annotate screen (canvas, pinch-zoom, two-tap dims, sheet under photo, reading field, name+chips, segmented control, tolerance, Save/Delete)
This is the screen where HIG and DESIGN.md most directly interact — see §6 for the one open question.

| HIG says | On the web this means… |
|---|---|
| **Zoom** and **rotate** are standard system gestures on iOS/iPadOS (two-finger pinch/drag) [18] | `touch-action: none` on the canvas element + custom Pointer Events pinch handling (already planned) is the correct low-level approach; there's no native `pinch-zoom` CSS gesture to defer to, so the app must implement HIG's *behavior* even though it can't use the *API* |
| Give people more than one way to interact — never assume a gesture is available to everyone [19] | The two-tap-to-dimension flow has no fallback for someone who can't pinch/drag precisely — worth a backlog note, not a v0 blocker, but flag it in accessibility follow-ups |
| Sheets: "designed for iPhone… detents… large is fully expanded, medium is about half" — and sheets are **modal or nonmodal** only in iOS/iPadOS specifically (every other platform's sheet is always modal) [20] | This app's reading/name panel sits in-flow under the photo, not as a `UISheetPresentationController` overlay — see §6, this is the one place worth flagging explicitly to Dwight |
| Text field: show a hint via placeholder + separate label (placeholder disappears once typing starts) [21] | Reading field needs *both* a placeholder and a persistent caption-size label above it — don't rely on placeholder alone once the user starts typing |
| iOS text field: leading = purpose icon, trailing = feature button (e.g. clear) [21] | Consistent with DESIGN.md's mono numeric field; a clear/× affordance on the reading field would be idiomatic |
| Customize the Return key type when it clarifies the flow (`submitLabel`/`UIReturnKeyType`) [22] | This *is* `enterkeyhint`. `enterkeyhint="next"` on the reading field, `enterkeyhint="done"` on the name field — already spec'd in SPEC.md §5, directly HIG-aligned, not just an iOS quirk |
| Custom controls placed above the keyboard should use the keyboard layout guide, standard padding, and (if the rest of your UI uses Liquid Glass) adopt it there too for consistency [22] | The reading/name panel effectively acts as an input accessory view once the keyboard is up; use `visualViewport` (already spec'd) to replicate `UIKeyboardLayoutGuide` behavior in the browser |
| Segmented control: use to switch between closely related subviews/choices; keep segment content sizes similar [15] | Length/Diameter/Depth segmented control is a textbook fit |
| Undo/redo: people expect to undo repeatedly, and (on iPhone specifically) via **shake-to-undo** or a three-finger swipe [23] | Neither gesture is available to a web app in the same way; Delete-on-a-selected-dimension is this app's only "undo," which is an acceptable v0 substitute — just don't claim shake-to-undo support |
| Validate dynamically, give feedback the moment a problem is detected, don't let people advance past required data silently [24] | Matches DESIGN.md's inline-error/disabled-Save pattern exactly — no alert needed for field validation, only for the recapture/delete confirmations |

### Settings (one toggle)
| HIG says | On the web this means… |
|---|---|
| Use the **switch** style only inside a list row, with no separate label needed — row content supplies context [15] | Matches — a single list row with a trailing switch, no extra caption |
| Default switch color is green; changing it to the app accent is fine as long as contrast against the "off" state stays perceptible [15] | Using `cc-amber` for the "on" state is HIG-sanctioned, not a deviation — just verify off vs on contrast |

### Debug (timer list, CSV)
No dedicated HIG component applies — it's a list (Lists and tables §13 applies for row styling) plus
an export action (Sharing/exporting icon: `square.and.arrow.up` per the Standard Icons list [25]).
Treat it like any other list screen; no special HIG guidance beyond what Parts/Part already cover.

### Cross-cutting patterns
| Pattern | HIG says | On the web this means… |
|---|---|---|
| Empty states | No explicit HIG "empty state" component page exists; general guidance is to show something immediately rather than a blank wait, and to make clear what to do next [26] | DESIGN.md's one-line copy + primary button for the empty Parts list is a reasonable, HIG-consistent minimal pattern |
| Loading | "The best loading experience finishes before people become aware of it"; show placeholder content immediately; avoid vague labels like "Loading…" [26] | DESIGN.md's "Decoding…" pill is *more* specific than HIG's own bar (HIG explicitly calls out vague loading copy as something to avoid) — good, keep it |
| Modality | Present modally only with clear benefit; always give an obvious dismiss; confirm before losing unsaved data [27] | The in-flow annotate panel is deliberately *non*-modal — consistent with HIG's own preference to avoid modality when a task can stay in the parent context [27][20] |
| Destructive confirmation | Alert vs action sheet: alert = confirm/cancel a consequence; action sheet = offer choices tied to an action the person initiated [16][17] | Recapture/Delete-dimension → alert (2 buttons). If a future "what do you want to do with this draft" flow appears (3+ choices), that's action-sheet territory, not alert territory |
| Keyboard toolbar | `inputAccessoryView`/keyboard layout guide is the native equivalent of a persistent control bar above the keyboard [22] | Not required here since the reading/name fields already sit above the keyboard by scroll position — no extra accessory bar needed |

Sources: [13] .../lists-and-tables · [14] .../progress-indicators · [15] .../segmented-controls,
.../toggles · [16] .../alerts · [17] .../action-sheets · [18] .../gestures · [19] .../accessibility ·
[20] .../sheets · [21] .../text-fields · [22] .../virtual-keyboards · [23] .../undo-and-redo · [24]
.../entering-data · [25] .../icons#Standard-icons · [26] .../loading, .../feedback · [27] .../modality

---

## 3. Colour: mapping amber/teal onto HIG

HIG's model is **one tint colour** per app plus the **system semantic colours** (label tiers,
separators, fills, backgrounds) for everything else — colour is reserved for "elements that truly
benefit from emphasis," and prominent (colour-filled) buttons should number one or two per screen,
not be the default for every action [2][9].

DESIGN.md's amber/teal system is **two** accents with **two distinct meanings** (tappable vs
live/verified) rather than one brand tint — that's a real deviation from "pick one accent colour,"
but it's a deviation HIG itself anticipates: "avoid using the same colour to mean different things…
use colour consistently, especially when it communicates status or interactivity" [28]. Two colours,
each locked to one meaning and never mixed, is more HIG-consistent than one colour doing double duty
for both "you can tap this" and "this is confirmed." The risk HIG flags isn't accent count, it's
*inconsistent* use of whichever colours you pick — and DESIGN.md's "never mix them" rule already
guards against that.

Recommendation: keep both accents, but audit every amber use against "is this actually the one or
two most prominent actions on this screen" — DESIGN.md's current usage (primary buttons, canvas
overlays, links) risks amber sprawling past "one or two prominent controls" on screens like Annotate,
which has a primary Save button *and* amber-styled canvas handles *and* amber value pills all
onscreen together. That's likely fine because the canvas elements are a different *system* (drawing
overlay, not UI chrome) from the button — but it's worth a conscious check, not an assumption.

Never colour-alone: HIG requires an additional non-colour signal wherever colour carries meaning [29].
DESIGN.md already does this (check/warning icons on flagged rows, text on invalid inputs) — confirmed
compliant, not just good practice.

Dark-mode-specific rules [6]:
- **Base vs elevated backgrounds** — a foreground layer (sheet, popover) should read as "advancing"
  via a lighter background than its parent. DESIGN.md has only `cc-ground`/`cc-surface`/`cc-surface-2`
  as three flat tiers, not a base/elevated *pair per tier* — acceptable for v0, but if a true modal
  ever appears (not the in-flow panel), it should get its own lighter tier rather than reusing
  `cc-surface`.
- **Avoid pure black** — not stated as a rule in current HIG prose, but implied by "Apple's grays are
  calibrated for OLED and elevation" **[secondary]**, and DESIGN.md's `cc-ground` (`#17181A`) already
  isn't pure black — compliant.
- **Desaturate/soften, don't just darken** — HIG's own dark palette isn't a simple inversion of light
  [6]. `cc-amber`/`cc-teal` are already tuned as dark-mode-native colours (not light-mode colours
  dimmed down), which is the right approach.
- **Contrast**: strive for 7:1 on custom colour pairs in dark mode, especially small text [6] — see
  §1; DESIGN.md clears this already.

Source: [2][9] as in §1/§2 · [28] .../color best practices · [29] .../accessibility, inclusive color
· [6] .../dark-mode

---

## 4. Icons

**SF Symbols licence is Apple-platforms-only and does not cover the web.** The HIG's own SF Symbols
page points to "terms and conditions" without quoting them [30]; the actual licence agreement (not
independently re-fetched here — **[secondary]**, sourced from Apple developer-forum threads quoting
it) restricts SF Symbols to "creating user interfaces… running on Apple's iOS, iPadOS, macOS, tvOS
or watchOS operating systems" and separately bars using symbols (or confusingly-similar glyphs) as
app icons/logos/trademarks [31]. A Safari PWA is web content, not a "software product running on"
those operating systems in the sense the licence means — bundling actual SF Symbols glyph assets
(SVGs exported from the SF Symbols app, or the symbol font) into this app's web bundle is out. This
is worth stating plainly to the owner: it's not a style preference, it's a licence boundary.

Closest open alternatives with comparable geometry: **Lucide** (successor to Feather, 2px stroke,
24×24 grid — closest optical match to SF Symbols' regular weight) or **Tabler Icons** (also 2px,
slightly more rounded terminals). DESIGN.md §10 already names this pair — this confirms it's the
right call, not just a placeholder choice.

This app's ~12 icons, with **HIG-confirmed** symbol names from the Standard Icons list [25] marked ✓,
and well-known-but-not-listed-there names marked with an em dash:

| Purpose | SF Symbol name | In HIG's Standard Icons table? |
|---|---|---|
| Back | `chevron.left` | — (back chevron is a system-drawn nav element, not a listed standalone icon) |
| Capture | `camera` | — |
| Import from library | `photo` | — |
| Add | `plus` | ✓ |
| Delete | `trash` | ✓ |
| Confirm / saved | `checkmark` | ✓ |
| Warning / flagged | `exclamationmark.triangle` | — |
| Export / share | `square.and.arrow.up` | ✓ |
| Settings | `gearshape` | — |
| Measurement | `ruler` | — |
| Zoom out / in | `minus.magnifyingglass` / `plus.magnifyingglass` | — (note: SF Symbols names these magnifying-glass-first, not `magnifyingglass.minus/plus`) |
| Cancel / clear | `xmark` | ✓ |

Sources: [25] .../icons#Standard-icons · [30] .../sf-symbols · [31] SF Symbols license agreement,
via Apple Developer Forums discussion threads (license PDF itself not independently fetched here —
flagged as secondary)

---

## 5. Do / don't for a "native-feel" PWA, ranked by impact

1. **Do** keep 44×44 pt (44px at 1x CSS pixel = device point on iOS Safari) as the hard floor for
   every tappable target — HIG-verified, not just a shop-glove nicety [1][2].
2. **Do** put a large title only on the Parts list (root) and small titles everywhere pushed below
   it — this single cue does more for "feels native" than any color or font choice [10].
3. **Do** use `enterkeyhint` and `inputmode="decimal"` correctly — this is the actual HIG-equivalent
   behavior (Return key customization, numeric keyboard type) SPEC.md already mandates [21][22].
4. **Do** keep prominent (amber-filled) buttons to one or two per screen — audit Annotate specifically
   [2].
5. **Do** treat recapture/delete confirmations as alerts (2 buttons, destructive style), not custom
   modals or toasts [16].
6. **Do** respect `env(safe-area-inset-*)` and avoid `position: fixed` over content that resizes with
   the keyboard — already spec'd, confirmed HIG-aligned [12].
7. **Do** add `color-scheme: dark` and use a base/elevated distinction if a true modal is ever added
   [6].
8. **Don't** ship actual SF Symbols assets — licence violation for web content [31].
9. **Don't** promise full Dynamic Type support — Safari doesn't expose it to CSS; survive 120–150%
   zoom instead, which is what SPEC.md already targets.
10. **Don't** use an action sheet for the recapture/delete confirmations — those are consequence
    confirmations (alert), not choice menus (action sheet) [16][17].
11. **Don't** rely on colour alone anywhere new — DESIGN.md already does this right; don't regress
    it when adding "modern Apple" polish [29].
12. **Don't** add a persistent status bar, fake large-title-on-every-screen, or other chrome HIG
    reserves for the root screen — restraint here reads more native than more chrome would.
13. **Don't** invert the reading/name panel into a real modal sheet without discussing it with the
    owner first — see §6, this is a real open question, not a settled HIG violation.
14. **Don't** chase exact system pt values that HIG no longer publishes (margins, bar heights) as if
    they were gospel — DESIGN.md's own token scale is close enough that matching an unpublished
    number precisely isn't worth the churn.
15. **Don't** treat "Liquid Glass" as this brief's job — that's the sibling doc; don't duplicate or
    contradict it here.

---

## 6. Open questions for the owner

**1. Is the in-flow reading/name panel HIG-consistent, or should it become a real sheet?**
HIG's sheet page explicitly frames iOS sheets as able to be **nonmodal** — "people use its
functionality to affect the parent view without dismissing the sheet" [20] — which is closer to what
DESIGN.md already does (a panel under the photo, not a dismissible overlay) than it might first
appear. But HIG's sheet *anatomy* still assumes a system sheet: a **grabber**, **detents**
(large/medium), swipe-to-dismiss, Cancel/Done placement in a top toolbar [20]. DESIGN.md's panel has
none of that — it's simply laid out in the document flow. **My read:** the *non-modality* is
HIG-consistent; the *absence of sheet affordances* is a deliberate, defensible departure given the
"hands stay on the part" principle in DESIGN.md §1 (a resizable, swipeable sheet would fight a
one-thumb capture workflow). Recommend keeping the in-flow panel as-is, but don't call it a "sheet"
in any user-facing copy or code comments — it isn't one by HIG's definition, and mislabeling it will
confuse the next person who reads DESIGN.md against real UIKit sheet behavior.

**2. Dark-only vs supporting both appearances.**
HIG allows dark-only "in rare cases," specifically naming immersive-media viewing as the example
where a permanently dark appearance helps people focus [6]. A shop tool used outdoors/under work
lighting is a reasonable extension of that rationale, but it's a stretch, not a direct match — HIG's
default expectation is that apps support both and let the system's Auto setting switch them [6].
**Recommendation:** keep dark-only for v0 (DESIGN.md §10 already made this call) — the "glove-tolerant,
glance-and-back-to-work" principle is a legitimate rare-case justification — but log it as a real,
named departure rather than an oversight, since HIG's default assumption is both appearances.

**3. Custom fonts (Space Grotesk / IBM Plex) vs SF Pro.**
HIG doesn't prohibit custom fonts — it just requires "recommended default and minimum sizes" be
respected for whatever font is used, and warns against thin/light weights at small sizes [5]. Using
custom display/body fonts is fully within HIG's rules as long as the *type-style hierarchy and
sizing* (§1's table) is preserved even though the *typeface* isn't SF. The "modern Apple, Liquid
Glass, more native feel" direction pulls toward SF Pro for maximum platform-nativeness, since SF Pro
is what makes the OS's own optical sizing/weight-matching with SF Symbols work seamlessly [5].
**Recommendation:** this is a real tension between "native feel" (→ SF Pro) and "keep the app's own
identity" (→ Space Grotesk/IBM Plex, already chosen and reflected in DESIGN.md). Since icons are
already moving to Lucide/Tabler (not SF Symbols, per §4), the app has already partly opted out of SF
Pro/SF Symbols visual unity — keeping IBM Plex for body text is consistent with that choice. Suggest
keeping the current fonts, not switching to SF Pro, but tightening the *type-style scale itself*
(sizes, weights, leading) to match §1's table precisely, since that structural rhythm is what reads
as "native," more than the specific typeface does.

**4. Full-width amber Save/Export buttons vs a smaller tinted style.**
HIG's guidance is behavioral, not size-based: prominent (colour-filled) styling signals "the most
likely action in this view," and should be limited to one or two per screen — it says nothing against
full width specifically [2]. DESIGN.md's full-width Primary button pattern is HIG-consistent as long
as the "one or two per screen" rule holds. **Recommendation:** no change needed; this isn't actually
in tension with HIG, despite reading like a very non-iOS-native choice at first glance (iOS system
buttons are often content-width, not edge-to-edge) — full-width is common in Apple's own first-party
apps for the *single* most likely action on a screen (e.g., "Get Directions," checkout flows), so
this reads as reasonably native already.

Sources: [20] .../sheets · [6] .../dark-mode · [5] .../typography · [2] .../buttons
