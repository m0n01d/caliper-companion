# Liquid Glass, and how far CSS can honestly go

Companion to `DESIGN.md`. That doc owns dark shop-UI tokens, typography, and component specs; a
sibling HIG doc covers general iOS 26 conventions. This doc covers one thing only: the glass
material system, and what a PWA in iOS Safari can and cannot honestly reproduce of it.

**Sourcing note up front:** Apple's own HIG and developer-documentation pages
(`developer.apple.com/design/human-interface-guidelines/materials`,
`.../technologyoverviews/liquid-glass`, `.../technologyoverviews/adopting-liquid-glass`) are
client-rendered SPAs — direct fetch returns only the page `<title>`, no body text. Everything
attributed to those pages below comes from search-indexed snippets of them (Google's cache of the
rendered text) or from WWDC session notes/press coverage that quote them, never invention. Where a
claim is secondary-only (blogs, not Apple), it's marked **[secondary]**. Treat anything not marked
that way as Apple's own words or a close paraphrase of an indexed snippet.

## 1. What Liquid Glass actually is

Liquid Glass is Apple's iOS 26/WWDC25 cross-platform material: "a digital meta-material that
dynamically bends and shapes light," combining "the optical properties of glass with a
fluidity that only Apple can achieve," introduced June 9, 2025 and shipped across iOS 26, iPadOS
26, macOS Tahoe 26, watchOS 26, tvOS 26.
[Apple Newsroom](https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/)

**Layer model.** The system has two layers: a **content layer** (your app's actual information —
text, photos, lists) and a **floating controls/navigation layer** that sits above it made of
Liquid Glass — tab bars, toolbars, sliders, buttons. Apple's explicit guidance: glass is "best
reserved for the navigation layer. Avoid putting glass in the content layer and avoid putting
[glass] within or on top of other glass elements." [WWDC25 "Meet Liquid Glass" / HIG, via
search](https://developer.apple.com/videos/play/wwdc2025/219/) · [HIG materials, via
search](https://developer.apple.com/design/human-interface-guidelines/materials)

**Optical model.** Three components layer together: **highlight** (light casting and movement
across the surface), **shadow** (depth separation from what's behind it), and **illumination**
(the material's own light-bending property). **[secondary, CSS-Tricks paraphrase of
Apple's framing]** Concretely:
- **Lensing/refraction** — background content is "bent and warped rather than scattering light,"
  giving a gel-like feel at the edges, not a flat blur.
- **Specular highlights** — a highlight that moves across the surface in response to device tilt
  and touch, like light catching a curved edge.
- **Adaptive tint** — the material samples color from content beneath it and "light from colorful
  content nearby can spill onto its surface"; components can independently flip between light and
  dark rendering depending on what's under them.
[CSS-Tricks technical breakdown](https://css-tricks.com/getting-clarity-on-apples-liquid-glass/) ·
[WWDC25 "Meet Liquid Glass" notes](https://developer.apple.com/videos/play/wwdc2025/219/)

**Two variants — never mixed:**

| Variant | Behavior | When Apple says to use it |
|---|---|---|
| **Regular** | Full adaptive effects (tint, light/dark switching); legible over any content at any size; anything can sit on top of it | Default for almost everything — toolbars, tab bars, nav bars, standard controls |
| **Clear** | No adaptive behavior; permanently more transparent; needs a **dimming layer** under it for legibility | Only when: content is media-rich, a dimming layer won't hurt that content, and what's on top is bold/bright (e.g. a fullscreen video player's controls) |

[Search-indexed HIG/WWDC summary](https://developer.apple.com/videos/play/wwdc2025/356/) —
"Get to know the new design system," WWDC25 session 356.

**Concentric corners.** Glass controls nest inside the rounded corners of their container so the
control's corner radius and the container's corner radius share a center — "the capsule's geometry
naturally supports concentricity... echoed in bars, buttons, and the rounded corners of grouped
table views." A component's corner radius is *derived from* its container's, not set
independently. [WWDC25 356, via search](https://developer.apple.com/videos/play/wwdc2025/356/)

**Morphing transitions.** Glass elements animate as fluid shape changes rather than crossfades —
e.g. a button expanding into a menu, or two nearby glass shapes merging when they get close enough
(a `spacing` parameter controls the merge distance). **[secondary, based on SwiftUI API
docs indexed via search]** [Reference](https://github.com/conorluddy/LiquidGlassReference)

**Scroll-edge effects.** Where a scroll view meets a safe-area edge (top/bottom bars), the glass
above it modulates — "as text scrolls underneath, shadows become more prominent to create
separation" — a configurable edge treatment (soft fade vs. hard edge), not a fixed blur strip.
[WWDC25 "Meet Liquid Glass," via search](https://developer.apple.com/videos/play/wwdc2025/219/) ·
[createwithswift.com on scroll-edge style](https://www.createwithswift.com/define-the-scroll-edge-effect-style-of-a-scroll-view-for-liquid-glass/)
**[secondary for the createwithswift detail]**

**Accessibility modes change the material, not just contrast:** Reduced Transparency makes glass
"frostier" and obscures more of what's behind it (doesn't remove translucency outright); Increased
Contrast makes elements "predominantly black or white" with a contrasting border, effectively
turning glass into a bordered solid; Reduced Motion "decreases the intensity of some effects and
disables any elastic properties." [WWDC25 "Meet Liquid Glass," via
search](https://developer.apple.com/videos/play/wwdc2025/219/)

**Where Apple says not to use it:** content areas (text-heavy reading surfaces, lists of data),
glass directly on glass, and — per the variant table above — Clear without a dimming layer or over
low-contrast content. The unifying rule across every source: **glass is chrome, not content.**

## 2. What the web can and cannot do

| Liquid Glass trait | Best CSS approximation | Fidelity | iOS Safari caveats |
|---|---|---|---|
| Frosted translucency | `backdrop-filter: blur(Npx) saturate(1.4–1.8)` + a semi-opaque `background` fill | **Good** | Needs `-webkit-backdrop-filter` *before* the unprefixed property (Safari required the prefix from Safari 9–17; omit it and pre-18 iOS gets no blur at all). Baseline as of late 2024, but budget for older installed PWAs. |
| Specular edge highlight | 1px inset top highlight via `box-shadow: inset 0 1px 0 rgba(255,255,255,.18)` (or a `::before` gradient border) | **Partial** | Static, not motion-reactive — real Liquid Glass highlights move with tilt/touch; CSS can only fake the resting-state catch-light, not the live specular response. |
| Lensing/refraction (edges bend background) | Nothing native. Closest: an SVG `feDisplacementMap`/`feGaussianBlur` filter, or a thin second blurred layer offset by a few px | **None–Partial** | SVG filter approach is broken/inconsistent in Safari (community reports "doesn't work in Safari"); not worth shipping. `backdrop-filter: blur()` alone does not bend, it averages — be honest that this trait is out of reach. |
| Adaptive tint from content beneath | `color-mix()` to blend a tint token with a sampled/approximate background color; or just a fixed low-alpha tint | **Partial** | `color-mix()` has solid Safari support (16.2+), but *sampling* the actual pixels under an element is not possible in CSS — you're choosing a tint by context (dark photo vs. light list), not reading it live. |
| Independent light/dark switching per component | `@media (prefers-color-scheme)` + manual per-component override, or a data-attribute theme scope | **Partial** | Works, but it's app-driven (you decide when a surface flips), not content-driven (the OS doesn't do it automatically based on what's under the glass). |
| Concentric corner radii | Derive child `border-radius` from parent `border-radius − padding` by convention/token, not automatically | **Partial** | No native "concentric" primitive. `corner-shape`/`superellipse()` (the actual squircle curve) is Chromium-only as of 2026 — **no Safari support**; standard `border-radius` degrades gracefully but is a circular arc, not Apple's superellipse. Don't block on it. |
| Morphing shape transitions | `transition` on `border-radius`/`clip-path`/`width`/`height` with a spring-like easing curve; View Transitions API where available | **Partial** | Doable for simple expand/collapse; true multi-shape *merging* (two pills combining into one) needs FLIP-style JS choreography — plan for it only on the highest-value interaction, not everywhere. |
| Scroll-edge fade/shadow | A gradient mask (`mask-image: linear-gradient(...)`) or shadow that intensifies via a scroll listener | **Good** | Cheap and reliable; don't gate this on `backdrop-filter` support at all. |
| Reduced transparency fallback | `@media (prefers-reduced-transparency: reduce)` → swap to opaque fill | **None on iOS Safari today** | **WebKit has not implemented `prefers-reduced-transparency`** — cited reason is fingerprinting-vector concerns. [MDN compat data, via search](https://developer.mozilla.org/en-US/docs/Web/CSS/@media/prefers-reduced-transparency) It is real CSS (write it, it's free and correct for Chrome/desktop), but **it will never fire on an iPhone no matter what the user sets in Settings → Accessibility → Reduce Transparency.** You cannot detect that OS setting from web content. Compensate by keeping contrast high enough that glass never *depends* on the setting to stay legible (see §3, and DESIGN.md's 4.5:1 rule already forces this). |
| `backdrop-filter` cost on large/animated areas | Scope blur to small fixed-size chrome elements only; never blur a full-bleed sheet | — | `backdrop-filter` is one of the most expensive CSS properties in the engine; a single small toolbar is fine, a full-height glass sheet measurably drops scroll FPS, worse on older/mid-tier phones. **[secondary, multiple performance write-ups]** |
| Blur behind a live-repainting `<canvas>` | Avoid entirely, or blur a static snapshot instead of the live canvas | — | A `backdrop-filter` sampling a `<canvas>` that redraws every frame (this app's Annotate screen) forces the compositor to re-composite the blur on every canvas repaint — compounding cost, not additive. Don't put glass directly over the live photo canvas. |
| `position: sticky`/`fixed` + `backdrop-filter` | Prefer `sticky` scoped to the scroll container; put the blur/tint on an absolutely-positioned *child*, not the sticky/fixed element itself | — | Two distinct iOS Safari bugs, both current: (1) `fixed`/`sticky` elements carrying `backdrop-filter` can composite on a layer that lags scroll, visibly freezing mid-scroll on fast flicks; (2) **Safari 26 specifically scans `fixed`/`sticky` elements near viewport edges and reads their `background-color`/`backdrop-filter` to auto-tint the native status bar and toolbar chrome** — including elements merely `opacity: 0` (use `display: none` if something must be inert). Putting glass on a fixed bar can literally recolor Safari's own UI unpredictably. [Case study, via WebFetch](https://1ar.io/updates/safari-26-liquid-glass-web/) |

**Bottom line, bluntly:** CSS can sell *translucency* (blur + tint + a highlight edge) convincingly
at small scale on static chrome. It cannot sell *lensing* (the background visibly warping through
the glass), cannot sell a *live specular highlight* that tracks device motion, and cannot honor the
user's actual OS transparency-reduction preference. Anything that leans on those three will read as
"CSS glass," not Liquid Glass — better to under-claim (flat frosted panel, honest and cheap) than
over-claim (fake refraction that breaks on first inspection).

## 3. A CSS recipe for this app

### Tokens (add alongside DESIGN.md's `cc-` tokens, not replacing them)

```css
:root {
  /* fills */
  --glass-fill: rgba(35, 37, 39, 0.72);       /* cc-surface at ~72% */
  --glass-fill-strong: rgba(23, 24, 26, 0.82); /* cc-ground at ~82%, for over-photo chrome */
  --glass-stroke: rgba(244, 242, 236, 0.10);   /* cc-text at 10%, hairline edge */
  --glass-highlight: rgba(244, 242, 236, 0.16);/* top inset highlight */
  --glass-blur: 20px;
  --glass-saturate: 1.6;
  --glass-radius-sm: 14px;   /* matches cc-radius-lg neighborhood, rounder than opaque cards */
  --glass-radius-pill: 999px;
}

/* dark is the only mode per DESIGN.md §10, but keep the hook for the future */
@media (prefers-color-scheme: light) {
  :root {
    --glass-fill: rgba(255, 255, 255, 0.55);
    --glass-stroke: rgba(0, 0, 0, 0.08);
    --glass-highlight: rgba(255, 255, 255, 0.5);
  }
}
```

### Component classes

```css
.glass {
  background: var(--glass-fill);
  -webkit-backdrop-filter: blur(var(--glass-blur)) saturate(var(--glass-saturate));
  backdrop-filter: blur(var(--glass-blur)) saturate(var(--glass-saturate));
  border: 1px solid var(--glass-stroke);
  box-shadow: inset 0 1px 0 var(--glass-highlight), 0 1px 3px rgba(0,0,0,0.3);
  border-radius: var(--glass-radius-sm);
}

@supports not ((backdrop-filter: blur(1px)) or (-webkit-backdrop-filter: blur(1px))) {
  .glass {
    background: var(--cc-surface); /* fall back to a plain opaque cc-surface card */
    box-shadow: 0 1px 3px rgba(0,0,0,0.3);
  }
}

/* Safari can't tell us prefers-reduced-transparency (see §2) — so glass surfaces
   must already clear DESIGN.md's 4.5:1 contrast rule on their own, not rely on
   a fallback to become legible. This rule exists for other browsers that DO
   report the preference, and as a statement of intent. */
@media (prefers-reduced-transparency: reduce) {
  .glass {
    background: var(--cc-surface);
    -webkit-backdrop-filter: none;
    backdrop-filter: none;
  }
}
```

### Per-component calls, argued against the app's actual screens

| Component | Glass or solid? | Why |
|---|---|---|
| **Floating nav bar** (back/title row) | **Glass**, `sticky` not `fixed` | This is exactly the "navigation layer" Apple's glass is for. DESIGN.md already bans `position: fixed` over the canvas — that ban and the Safari-26 auto-tint bug in §2 point the same direction. Make it `position: sticky; top: env(safe-area-inset-top);` scoped inside the page's own scroll container (not the `<html>`/`<body>` root), so it never becomes one of the edge-hugging fixed elements Safari scans for chrome-tinting, and it naturally scrolls away on screens where DESIGN.md wants the canvas unobstructed. |
| **In-flow control sheet** under the Annotate photo (reading field, name field + chips, segmented control, Save) | **Opaque `cc-surface`, not glass** | Argue against glass here: this is DESIGN.md's content/input layer, exactly what HIG calls out as the wrong place for glass ("avoid putting glass in the content layer"). It also sits directly under a live-repainting `<canvas>` — §2's worst case for `backdrop-filter` cost. And it's dense with real inputs (44px fields, chips, a segmented control) where translucent-over-photo would hurt legibility for a glove-and-bench user glancing under shop lighting, which is the opposite of DESIGN.md's "no fake chrome" principle. Keep it a solid `cc-surface` card; save glass for the toolbar above it. |
| **Pills over the photo** (placement hints, level readout) | **Keep as scrim, not full glass** | DESIGN.md's `cc-scrim` (flat `#1A1B1DCC`) already does the job Clear-variant glass would do — legibility over unpredictable photo content — without needing a dimming layer or live blur sampling of a repainting canvas. A `backdrop-filter` pill directly over the canvas would re-trigger the canvas-blur cost problem every frame. Flat scrim is the *honest* choice, not a compromise: it's what Apple's own Clear variant effectively degrades to when a dimming layer is present anyway. |
| **Segmented control** | **Solid**, DESIGN.md spec as-is | It's a content-layer input (kind: Length/Diameter/Depth), inside the opaque control sheet above — no reason to break that sheet's material partway through. |
| **Primary button** ("Save dimension") | **Solid `cc-amber` tint, not glass** | Apple's own prominence guidance: glass is for *navigational chrome*, and a colored/tinted solid fill is how Apple signals a *prominent action* button distinctly from a glass toolbar button. A glass Save button would visually demote the one action this screen exists for. Keep DESIGN.md's solid amber spec unchanged. |
| **Chips** (name suggestions, face picker) | **Solid**, DESIGN.md spec as-is | Same content-layer logic as the segmented control; also small/dense enough that per-chip blur would be a real perf hit for no visible gain. |

### The "no `position: fixed` over the canvas" rule, reconciled

DESIGN.md already forbids fixed bars over the canvas for scroll-with-content reasons. Section 2's
research adds a second, independent reason: Safari 26 reads `fixed`/`sticky` elements near screen
edges to auto-tint its own chrome, and `fixed` + `backdrop-filter` has a known scroll-lag
compositing bug on iOS. A floating glass toolbar can still exist — as `position: sticky` scoped to
the in-page scroll container (never to the viewport/root), so it (a) scrolls normally with content
per DESIGN.md, (b) never becomes one of the always-anchored elements Safari's tinting heuristics
target, and (c) sidesteps the fixed+blur scroll-lag bug because sticky-in-container isn't a
top-level fixed layer. If a screen has no natural scroll container long enough to make sticky
meaningful (e.g. a short Settings screen), skip glass for that bar entirely and use a plain
`cc-surface` header — don't reach for `fixed` just to keep the glass.

## 4. Motion

Liquid Glass's vocabulary: **morph** (shape-to-shape transitions, e.g. buttons expanding into
menus, pills merging), **spring** physics (elastic, slightly overshooting settle — disabled
entirely under Reduced Motion per §1), and **scroll-edge** reactivity (shadow/opacity intensifying
as content passes under a glass edge). [WWDC25 "Meet Liquid Glass," via
search](https://developer.apple.com/videos/play/wwdc2025/219/)

What to keep on the web, and what DESIGN.md already has right: DESIGN.md's existing motion rule
(opacity/position, 120–160ms, `cubic-bezier(0.2, 0, 0, 1)`, no bounce) is *already* the correct
restrained subset — don't add spring overshoot on top of it. For glass-specific moments (toolbar
appearing/disappearing, a pill's `backdrop-filter` fading in) stay in the 120–200ms range and use
an ease-out curve that *decelerates* into place (a cheap, honest stand-in for "spring settle"
without implementing actual physics). Respect `prefers-reduced-motion: reduce` by dropping to 0ms
exactly as DESIGN.md already specifies — this one *does* work reliably in Safari, unlike
`prefers-reduced-transparency`.

## 5. Do / don't (ranked, 12 max)

1. **Don't fake lensing/refraction with SVG filters "for authenticity."** It's the biggest
   self-defeating move teams make — the effect is broken/inconsistent in Safari, costs the most
   performance, and a half-working warp reads as more fake than no warp at all.
2. **Do reserve glass for chrome (nav/toolbar), never for content or input surfaces.** This is
   Apple's own rule, not just a performance shortcut.
3. **Don't put `backdrop-filter` directly over a live-repainting `<canvas>`** — the Annotate photo
   canvas is the one place in this app where that mistake is easy to make.
4. **Do put `-webkit-backdrop-filter` before the unprefixed property, always, on every glass rule.**
5. **Don't rely on `prefers-reduced-transparency` to save legibility on iOS** — it doesn't fire in
   Safari; contrast has to be right on the glass surface itself.
6. **Do use `sticky` scoped to a scroll container instead of `fixed`** for any floating glass bar,
   both for DESIGN.md's existing reasons and to dodge Safari 26's chrome auto-tinting scan.
7. **Don't mix Regular and Clear (or "glass on glass")** — nest glass panels only for genuinely
   separate chrome layers, never a glass pill on a glass toolbar.
8. **Do treat concentric corners as a token relationship (child radius derived from parent), not
   a CSS feature** — `corner-shape`/`superellipse()` isn't there yet on Safari.
9. **Don't animate `backdrop-filter` blur radius itself** — animate opacity/transform of a
   pre-blurred layer instead; animating the filter value is the expensive path.
10. **Do keep one real elevated surface (`cc-surface`, opaque) for every dense-input area** —
    Annotate's control sheet is the flagship case for this.
11. **Don't add glass because it's the fashionable material** — every glass instance should map to
    Apple's own criterion: is it navigation, is it a floating control, is it *not* content.
12. **Do test glass surfaces in Safari's real Reduce Transparency / Increase Contrast modes**, even
    though CSS can't detect them — verify by eye that the app doesn't depend on that detection.

## 6. Recommendation for this app in five sentences

Use real Liquid Glass CSS (`backdrop-filter: blur() saturate()`, a 1px inset highlight, a stroke)
in exactly one place: the sticky top nav bar, because that's the one surface that is genuinely
navigation chrome and genuinely benefits from feeling like it floats over the part on the bench.
Keep everything DESIGN.md already calls content or input — the Parts list rows, the Annotate
control sheet, chips, the segmented control, the primary Save button — as opaque `cc-surface`/
`cc-amber` exactly as specified, both because Apple's own guidance keeps glass out of content and
because this app's actual context (gloved hands, bright bench light, glance-and-tap) needs the
highest-contrast surface it can get, not a translucent one. Leave the over-photo hint pills as
DESIGN.md's flat `cc-scrim`, not glass, since a `backdrop-filter` pill sitting on a live-repainting
canvas is the single worst performance case this material has. Skip the fixed-position bar
question entirely by making the glass nav bar `sticky` inside the scroll container, which
satisfies DESIGN.md's existing "no fixed over the canvas" rule and avoids Safari 26's chrome
auto-tinting side effect on fixed/sticky edge elements. The net effect should be "one native-feeling
floating bar in an otherwise honest, high-contrast dark shop UI" — not a glass reskin of the whole
app, which the sources above suggest Apple itself would call a content-layer misuse.

---

## Sources consulted

Fetched directly (WebFetch):
- [Apple Newsroom, June 2025 announcement](https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/)
- [MDN: `backdrop-filter`](https://developer.mozilla.org/en-US/docs/Web/CSS/backdrop-filter)
- [MDN: `prefers-reduced-transparency`](https://developer.mozilla.org/en-US/docs/Web/CSS/@media/prefers-reduced-transparency)
- [CSS-Tricks: Getting Clarity on Apple's Liquid Glass](https://css-tricks.com/getting-clarity-on-apples-liquid-glass/)
- [1ar.io: Safari 26 Liquid Glass web bugs case study](https://1ar.io/updates/safari-26-liquid-glass-web/)

Attempted but blocked (Apple's HIG/dev-docs pages are client-rendered SPAs; WebFetch returned only
the `<title>`, no body — content below was recovered via WebSearch's indexed snippets of the same
pages instead):
- `developer.apple.com/design/human-interface-guidelines/materials`
- `developer.apple.com/documentation/technologyoverviews/liquid-glass`
- `developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass`
- `wwdcnotes.com` session pages (404'd on the specific paths tried)

Via WebSearch (indexed snippets of Apple's own pages, WWDC session notes, and secondary sources —
each claim above is marked `[secondary]` where the source is not Apple's own text):
- [WWDC25 "Meet Liquid Glass" (session 219)](https://developer.apple.com/videos/play/wwdc2025/219/)
- [WWDC25 "Get to know the new design system" (session 356)](https://developer.apple.com/videos/play/wwdc2025/356/)
- [createwithswift.com: scroll-edge effect style](https://www.createwithswift.com/define-the-scroll-edge-effect-style-of-a-scroll-view-for-liquid-glass/)
- [conorluddy/LiquidGlassReference (GitHub)](https://github.com/conorluddy/LiquidGlassReference)
- [Squircle.js blog: `corner-shape`/`superellipse()` browser support, 2026](https://squircle.js.org/blog/squircles-in-css)
- MDN `color-mix()` (support confirmed via search; direct fetch 404'd on the specific URL tried)
- Multiple glassmorphism-recipe and iOS-Safari-`backdrop-filter`-performance write-ups (2025–2026),
  cited inline where used **[secondary]**
