// Icon — the app's icon set, inlined as SVG (DESIGN.md §11.1 "Icons"): Lucide
// outline paths, 2 px stroke, 20 px in text and 24 px in icon buttons. One
// component, no icon font, no dependency.
//
// Path data: lucide-static v1.47.0 (https://lucide.dev), fetched from
// https://unpkg.com/lucide-static@1.47.0/icons/<name>.svg. Lucide is ISC
// licensed: portions copyright (c) 2013-2022 Cole Bemis (Feather, MIT), all
// other copyright (c) 2022-present Lucide Contributors. Icon → file mapping:
// Trash = trash-2, TriangleAlert = triangle-alert, CircleCheck = circle-check,
// ZoomIn/ZoomOut = zoom-in/zoom-out; the rest are the lowercase name.

type name =
  | ChevronLeft
  | ChevronRight
  | Camera
  | Image
  | Plus
  | Trash
  | Check
  | TriangleAlert
  | Share
  | Settings
  | Ruler
  | ZoomIn
  | ZoomOut
  | X
  | CircleCheck
  | Bug

let shapes = (name: name): React.element =>
  switch name {
  | ChevronLeft => <path d="m15 18-6-6 6-6" />
  | ChevronRight => <path d="m9 18 6-6-6-6" />
  | Camera =>
    <>
      <path
        d="M13.997 4a2 2 0 0 1 1.76 1.05l.486.9A2 2 0 0 0 18.003 7H20a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2h1.997a2 2 0 0 0 1.759-1.048l.489-.904A2 2 0 0 1 10.004 4z"
      />
      <circle cx="12" cy="13" r="3" />
    </>
  | Image =>
    <>
      <rect width="18" height="18" x="3" y="3" rx="2" ry="2" />
      <circle cx="9" cy="9" r="2" />
      <path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21" />
    </>
  | Plus =>
    <>
      <path d="M5 12h14" />
      <path d="M12 5v14" />
    </>
  | Trash =>
    <>
      <path d="M10 11v6" />
      <path d="M14 11v6" />
      <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6" />
      <path d="M3 6h18" />
      <path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" />
    </>
  | Check => <path d="M20 6 9 17l-5-5" />
  | TriangleAlert =>
    <>
      <path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3" />
      <path d="M12 9v4" />
      <path d="M12 17h.01" />
    </>
  | Share =>
    <>
      <path d="M12 2v13" />
      <path d="m16 6-4-4-4 4" />
      <path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8" />
    </>
  | Settings =>
    <>
      <path
        d="M9.671 4.136a2.34 2.34 0 0 1 4.659 0 2.34 2.34 0 0 0 3.319 1.915 2.34 2.34 0 0 1 2.33 4.033 2.34 2.34 0 0 0 0 3.831 2.34 2.34 0 0 1-2.33 4.033 2.34 2.34 0 0 0-3.319 1.915 2.34 2.34 0 0 1-4.659 0 2.34 2.34 0 0 0-3.32-1.915 2.34 2.34 0 0 1-2.33-4.033 2.34 2.34 0 0 0 0-3.831A2.34 2.34 0 0 1 6.35 6.051a2.34 2.34 0 0 0 3.319-1.915"
      />
      <circle cx="12" cy="12" r="3" />
    </>
  | Ruler =>
    <>
      <path
        d="M21.3 15.3a2.4 2.4 0 0 1 0 3.4l-2.6 2.6a2.4 2.4 0 0 1-3.4 0L2.7 8.7a2.41 2.41 0 0 1 0-3.4l2.6-2.6a2.41 2.41 0 0 1 3.4 0Z"
      />
      <path d="m14.5 12.5 2-2" />
      <path d="m11.5 9.5 2-2" />
      <path d="m8.5 6.5 2-2" />
      <path d="m17.5 15.5 2-2" />
    </>
  | ZoomIn =>
    <>
      <circle cx="11" cy="11" r="8" />
      <line x1="21" x2="16.65" y1="21" y2="16.65" />
      <line x1="11" x2="11" y1="8" y2="14" />
      <line x1="8" x2="14" y1="11" y2="11" />
    </>
  | ZoomOut =>
    <>
      <circle cx="11" cy="11" r="8" />
      <line x1="21" x2="16.65" y1="21" y2="16.65" />
      <line x1="8" x2="14" y1="11" y2="11" />
    </>
  | X =>
    <>
      <path d="M18 6 6 18" />
      <path d="m6 6 12 12" />
    </>
  | CircleCheck =>
    <>
      <circle cx="12" cy="12" r="10" />
      <path d="m16 9-5.5 5.5L8 12" />
    </>
  | Bug =>
    <>
      <path d="M12 20v-9" />
      <path d="M14 7a4 4 0 0 1 4 4v3a6 6 0 0 1-12 0v-3a4 4 0 0 1 4-4z" />
      <path d="M14.12 3.88 16 2" />
      <path d="M21 21a4 4 0 0 0-3.81-4" />
      <path d="M21 5a4 4 0 0 1-3.55 3.97" />
      <path d="M22 13h-4" />
      <path d="M3 21a4 4 0 0 1 3.81-4" />
      <path d="M3 5a4 4 0 0 0 3.55 3.97" />
      <path d="M6 13H2" />
      <path d="m8 2 1.88 1.88" />
      <path d="M9 7.13V6a3 3 0 1 1 6 0v1.13" />
    </>
  }

// Decorative by default (`aria-hidden`, the parent control carries the
// label). Pass `label` to make the icon itself the accessible content
// (`role="img"` + `aria-label`), e.g. a standalone status glyph.
@react.component
let make = (~name: name, ~size: int=24, ~label: option<string>=?) => {
  let px = Int.toString(size)
  <svg
    className="icon"
    width=px
    height=px
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth="2"
    strokeLinecap="round"
    strokeLinejoin="round"
    focusable="false"
    ariaHidden=?{label->Option.isNone ? Some(true) : None}
    role=?{label->Option.map(_ => "img")}
    ariaLabel=?label>
    {shapes(name)}
  </svg>
}
