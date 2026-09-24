# Snapkin brand v1 (2026-09-24)

The launch kit: the mark, the wordmark, the colours, the type, one graphic device and the voice.
The boards are on the design canvas (claude.ai artifact "Snapkin Launch"). The files are here.
The landing page that uses them is `site/` (https://snapkin.tools).

## Files

| File | Use |
|---|---|
| `snapkin-icon.svg` | The app icon, the same as `public/favicon.svg`. |
| `snapkin-mark.svg`, `snapkin-mark-dark.svg` | The mark alone, no tile. Ivory for dark grounds, bench black for light grounds. |
| `snapkin-lockup.svg`, `snapkin-lockup-dark.svg` | Mark and word. This is the primary logo. |
| `snapkin-wordmark.svg`, `snapkin-wordmark-dark.svg` | The word alone. Use it where the icon is already on screen. |
| `snapkin-tools-url.svg`, `snapkin-tools-url-dark.svg` | The address as a logo: `snapkin` plus `.tools` in pencil grey. Use it on video end cards and thumbnails. |
| `youtube-thumbnail-draft.png` | A 1280 × 720 thumbnail draft. Put your own photo or face on it before you use it. |
| `../../site/og.png` | The 1200 × 630 link-preview image of the landing page. |

All text is outlined to paths. No file needs a font to render.

## Mark

A ring with a ⌀ dimension across it: the camera lens and the caliper in one shape. It is the
shipped app icon (A14 "m2"), unchanged.

- Ivory `#F2F2F0` on bench black `#0E0F11`. The icon has no colour.
- Clear space is half the ring's diameter on all sides.
- Do not tilt, outline, recolour or add a shadow to the mark.
- The smallest size is 16 px (the favicon).

## Wordmark

- `snapkin`, lowercase, Space Grotesk 600, tracking −3 %, outlined to paths.
- Lockup: the ring is 0.82 em across. It is centred on the x-height. The gap to the `s` is 0.26 em.
  In the 100-unit drawing: x-height 48.6, ring 82, gap 26, ring centre 24.3 above the baseline.
- Space Grotesk is licensed under the SIL Open Font License 1.1 (`site/fonts/OFL.txt`).

## Colour

Three colours carry meaning. Nothing else gets colour.

| Name | Value | Meaning |
|---|---|---|
| Bench black | `#0E0F11` | The ground. |
| Graphite | `#1B1C1F` | Cards, rows, panels. |
| Ivory | `#F2F2F0` | Text, and the one thing to tap. |
| Pencil | `#A9ABAF` | Secondary text. |
| Sketch blue | `#38ABDF` | A measured value: lines, pills, rings. |
| Blue fill | `#0696D7` | "On": Snap, a selected segment, a switch. |
| Signal red | `#F0605A` | An error. The app only. |

These are the `src/theme.css` tokens. The brand adds no new colour.

## Type

| Role | Face | Where |
|---|---|---|
| Brand voice | Space Grotesk 600 | The wordmark, headlines, thumbnails. Never in the app. |
| Interface | SF Pro (system stack) | The app, and body text on the landing page. |
| Numbers | SF Mono (system stack) | Readings, feature names, values. |

## The dimension

The one graphic device is the dimension the app draws: dashed extension ticks, a line with filled
arrowheads, and a value pill in mono. Use it only to point at a real number. On a photo, draw it
exactly as the app does (`src/app/Overlay.res`), with the dark halo under every line and pill.

## Voice

- Tagline: **Calipers in. CAD out.** Alternates: "The napkin sketch, for real." "Photo to parameters."
- The name: snap + napkin. The back-of-the-napkin sketch, with real numbers on it.
- Say the number: "42.18 mm", not "precise measurements".
- Never promise pixel precision. The photo is the sketch. The caliper is the ruler.
- Use shop-floor words: part, face, edge, reading, feature. Do not use "AI-powered" or "magic".
- In the beta, write in the first person, in short sentences.

## Landing page

`site/` is a static page: HTML, one CSS file, SVG art, no JavaScript and no build step. It is the
root of `https://snapkin.tools`. The app is a separate site at `https://app.snapkin.tools`.
`site/README.md` has the preview, publish and DNS steps.

- The phone on the page is a static mock of the Annotate screen in `index.html`. The part is the
  golden fixture's hinge pin, drawn to scale (6.2 units per mm) with the app's overlay styles.
- `img/demo-poster.jpg` is a mock of the Part screen. The sandbox cannot decode H.264, so it is not
  a frame of the video.
- `snapkin-demo.mp4` is the demo from `scripts/demo-tour.mjs` (see `docs/demo/README.md`).
- `og:url`, `og:image` and `canonical` name `https://snapkin.tools/`. Change them if the domain changes.

## Beta sign-up

The form in `site/index.html` is off until a sign-up service is connected. The submit
button is `disabled` and a note says "Sign-ups open soon".

To connect it:

1. Make a form at a sign-up service and copy its form URL.
2. Put the URL in the form's `action`.
3. Remove `disabled` from the submit button and remove the `.form-note` paragraph.

The field names follow Kit: `email_address`, then `fields[phone]`, `fields[caliper]` and
`fields[first_part]`. Make the three custom fields in Kit first. Formspree and Basin accept any field
names, so the same form works with them. `_gotcha` is a honeypot field for Formspree.

Services checked on 2026-09-24:

| Service | Free tier | Notes |
|---|---|---|
| Kit | 10,000 subscribers (third-party sources; kit.com blocked the check) | Lets you email the whole list. Free-plan emails show Kit branding. Newsletter tools usually need a postal address in each email (CAN-SPAM); a PO box works. |
| Formspree | 50 submissions a month (checked on formspree.io) | Sends each sign-up to your inbox. A custom thank-you page is not free. |
| Cloudflare Worker + D1 | Free tier | You own the data. It needs code and a deploy. |
