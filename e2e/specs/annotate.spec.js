// annotate.spec.js — SPEC §8 M4 acceptance (the core screen), plus M3
// bullet 2 (EXIF orientation applied before any coordinate is computed) and
// M2 bullet 4 (reload mid-entry loses only the dimension being typed).
//
// Setup per test is the real user flow through the Parts and Capture pages'
// testids (docs/testids.md). Until those pages exist, `ANNOTATE_SEED=pouch`
// seeds the same part + face straight into PouchDB (same doc shapes as
// Store.res) so this spec can run against the Annotate page in isolation:
//
//   ANNOTATE_SEED=pouch npx playwright test --config=e2e/playwright.config.js --project=chromium annotate
//
// Tap geometry: the canvas publishes `data-transform="scale,tx,ty"` (image
// px → canvas CSS px) and `data-image-size="WxH"` (oriented), so a spec can
// compute exactly where a normalized point sits on screen at any zoom, click
// there, and read the resulting normalized point back from `pending-points`.
import {test, expect} from '@playwright/test'
import fs from 'node:fs'
import {fileURLToPath} from 'node:url'

const repoRoot = fileURLToPath(new URL('../..', import.meta.url))
const endJpg = repoRoot + 'fixtures/hinge_pin/end.jpg'
const topJpg = repoRoot + 'fixtures/hinge_pin/top.jpg'

// fixtures/README.md: end.jpg is stored landscape with EXIF orientation 6;
// oriented it is 1200×1600 and the hole is at (0.55, 0.30).
const HOLE = {x: 0.55, y: 0.3}
const ORIENTED = {w: 1200, h: 1600}
const TOL = 0.005

// ── setup ──────────────────────────────────────────────────────────────

async function openViaUi(page) {
  await page.goto('/')
  await page.getByTestId('new-part').click()
  await page.getByTestId('part-name').fill('Hinge pin')
  await page.getByTestId('part-create').click()
  await page.waitForURL(/#\/parts\/[^/]+$/)
  const partId = page.url().match(/#\/parts\/([^/]+)$/)[1]
  await page.goto(`/#/parts/${partId}/capture`)
  await page.setInputFiles('[data-testid=capture-file-end]', endJpg)
  await page.waitForURL(/#\/parts\/[^/]+\/faces\/[^/]+$/)
  const faceId = page.url().match(/\/faces\/([^/]+)$/)[1]
  return {partId, faceId}
}

async function openViaPouch(page) {
  await page.goto('/')
  await page.addScriptTag({path: repoRoot + 'node_modules/pouchdb/dist/pouchdb.js'})
  const base64 = fs.readFileSync(endJpg).toString('base64')
  const ids = await page.evaluate(async base64 => {
    const db = new window.PouchDB('caliper-companion')
    const now = new Date().toISOString()
    const partId = 'part:' + crypto.randomUUID()
    const faceId = 'face:' + crypto.randomUUID()
    await db.put({
      _id: partId, type: 'part', partId, name: 'Hinge pin', slug: 'hinge_pin', units: 'mm',
      notes: '', anchors: [], createdAt: now, updatedAt: now,
    })
    await db.put({
      _id: faceId, type: 'face', partId, kind: 'end', imageAttachment: 'image.jpg',
      pixelWidth: 1200, pixelHeight: 1600, levelDegrees: null, outline: null,
      capturedAt: now, updatedAt: now,
      _attachments: {'image.jpg': {content_type: 'image/jpeg', data: base64}},
    })
    await db.close()
    return {partId, faceId}
  }, base64)
  await page.goto(`/#/parts/${ids.partId}/faces/${ids.faceId}`)
  return ids
}

async function openFace(page) {
  const ids = process.env.ANNOTATE_SEED === 'pouch' ? await openViaPouch(page) : await openViaUi(page)
  await expect(page.locator('.shell-title')).toHaveText('End · Hinge pin')
  await expect(page.getByTestId('annotate-canvas')).toHaveAttribute('data-image-size', `${ORIENTED.w}x${ORIENTED.h}`)
  return ids
}

// ── geometry helpers ───────────────────────────────────────────────────

async function readTransform(page) {
  const canvas = page.getByTestId('annotate-canvas')
  // SPEC §8a A6: the view animates after p2 and after Save/Clear. While it
  // does, `data-transform` already reports the end state and a pointerdown
  // completes the animation first — but the zoom readout and the pixels
  // lag, so settle before reading geometry an assertion will compare.
  await expect(canvas).not.toHaveAttribute('data-autofit', 'fitting')
  const [s, tx, ty] = (await canvas.getAttribute('data-transform')).split(',').map(Number)
  const [w, h] = (await canvas.getAttribute('data-image-size')).split('x').map(Number)
  const box = await canvas.boundingBox()
  return {s, tx, ty, w, h, box}
}

function screenOf(t, n) {
  return {x: t.box.x + n.x * t.w * t.s + t.tx, y: t.box.y + n.y * t.h * t.s + t.ty}
}

function insideBox(t, p, margin = 4) {
  return (
    p.x >= t.box.x + margin && p.x <= t.box.x + t.box.width - margin &&
    p.y >= t.box.y + margin && p.y <= t.box.y + t.box.height - margin
  )
}

async function tapNormalized(page, n) {
  const t = await readTransform(page)
  const p = screenOf(t, n)
  expect(insideBox(t, p)).toBe(true)
  await page.mouse.click(p.x, p.y)
}

async function pendingPoints(page) {
  const text = await page.getByTestId('pending-points').textContent()
  return text.split(';').filter(Boolean).map(pair => pair.split(',').map(Number))
}

function expectNear(actual, expected) {
  expect(Math.abs(actual[0] - expected.x)).toBeLessThan(TOL)
  expect(Math.abs(actual[1] - expected.y)).toBeLessThan(TOL)
}

async function zoomTo(page, minFactor) {
  for (let i = 0; i < 12; i++) {
    if (Number(await page.getByTestId('zoom').textContent()) >= minFactor) return
    await page.getByTestId('zoom-in').click()
  }
  throw new Error(`zoom never reached ${minFactor}`)
}

// Drag from the canvas centre until the normalized point is on screen — a
// one-finger pan (Pointer Events), in steps small enough to stay inside the
// viewport.
async function panIntoView(page, n) {
  for (let i = 0; i < 12; i++) {
    const t = await readTransform(page)
    const p = screenOf(t, n)
    if (insideBox(t, p, 24)) return
    const cx = t.box.x + t.box.width / 2
    const cy = t.box.y + t.box.height / 2
    const dx = Math.max(-150, Math.min(150, cx - p.x))
    const dy = Math.max(-150, Math.min(150, cy - p.y))
    await page.mouse.move(cx, cy)
    await page.mouse.down()
    await page.mouse.move(cx + dx, cy + dy, {steps: 6})
    await page.mouse.up()
  }
  throw new Error('could not pan the point into view')
}

async function saveDimension(page, a, b, reading, name) {
  await tapNormalized(page, a)
  await tapNormalized(page, b)
  await expect(page.getByTestId('reading')).toBeFocused()
  await page.keyboard.type(reading)
  await page.keyboard.press('Enter')
  await expect(page.getByTestId('name')).toBeFocused()
  await page.keyboard.type(name)
  await page.keyboard.press('Enter')
}

// Saved dimensions' endpoints, from the `dimension-points` readout:
// `id:x1,y1;x2,y2|…` at 4 dp. Ids contain a colon, so split at the last one.
async function dimensionPoints(page) {
  const text = await page.getByTestId('dimension-points').textContent()
  return text.split('|').filter(Boolean).map(entry => {
    const i = entry.lastIndexOf(':')
    const [p1, p2] = entry.slice(i + 1).split(';').map(pair => pair.split(',').map(Number))
    return {id: entry.slice(0, i), p1, p2}
  })
}

// Press at a screen point and drag by (dx, dy) in a few steps — the first
// step alone is past the 8 px slop, so the drag arms on it.
async function dragFrom(page, p, dx, dy) {
  await page.mouse.move(p.x, p.y)
  await page.mouse.down()
  await page.mouse.move(p.x + dx, p.y + dy, {steps: 5})
  await page.mouse.up()
  await expect(page.getByTestId('dimension-points')).toHaveAttribute('aria-busy', 'false')
}

// A dimension's endpoints straight from PouchDB (the DB the app uses), so a
// test can wait for the write a saved-dimension drag issues on release
// before it reloads — the write is too quick to catch via `aria-busy`.
async function storedPoints(page, id) {
  if (!(await page.evaluate(() => Boolean(window.PouchDB)))) {
    await page.addScriptTag({path: repoRoot + 'node_modules/pouchdb/dist/pouchdb.js'})
  }
  return page.evaluate(async id => {
    const db = new window.PouchDB('caliper-companion')
    try {
      const doc = await db.get(id)
      return {p1: [doc.p1.x, doc.p1.y], p2: [doc.p2.x, doc.p2.y]}
    } finally {
      await db.close()
    }
  }, id)
}

function near(actual, expected) {
  return Math.abs(actual[0] - expected.x) < TOL && Math.abs(actual[1] - expected.y) < TOL
}

async function waitForStored(page, id, p1, p2) {
  await expect
    .poll(async () => {
      const s = await storedPoints(page, id)
      return near(s.p1, p1) && near(s.p2, p2)
    }, {timeout: 5000})
    .toBe(true)
}

// The normalized delta a drag of (dx, dy) screen px means under transform t.
function normalizedDelta(t, dx, dy) {
  return {x: dx / (t.w * t.s), y: dy / (t.h * t.s)}
}

// SPEC §8a A5: the Snap pill (`snap-toggle`, aria-pressed) — on by default,
// persisted in settings. `data-snap` on the canvas mirrors it.
async function setSnap(page, on) {
  const toggle = page.getByTestId('snap-toggle')
  if ((await toggle.getAttribute('aria-pressed')) !== String(on)) {
    await toggle.click()
  }
  await expect(toggle).toHaveAttribute('aria-pressed', String(on))
  await expect(page.getByTestId('annotate-canvas')).toHaveAttribute('data-snap', on ? 'on' : 'off')
}

// ── tests ──────────────────────────────────────────────────────────────

test.describe('annotate', () => {
  test('EXIF-rotated face: the hole taps to (0.55, 0.30) at 1× and at ≥3× (M3 b2, M4 b1)', async ({page}) => {
    await openFace(page)
    // This test is about tap geometry. The hole's rim is inside the snap
    // window at 1× (SPEC §8a A5, on by default), which would move the tap
    // off the centre; A5 has its own block below.
    await setSnap(page, false)

    const t1 = await readTransform(page)
    expect(t1.h).toBeGreaterThan(t1.w) // portrait after orientation
    expect(t1.box.height * t1.w).not.toBeCloseTo(t1.box.width * t1.h, 0) // not a stretched landscape
    expect(Number(await page.getByTestId('zoom').textContent())).toBeCloseTo(1, 2)

    await tapNormalized(page, HOLE)
    let pts = await pendingPoints(page)
    expect(pts).toHaveLength(1)
    expectNear(pts[0], HOLE)

    await zoomTo(page, 3)
    expect(Number(await page.getByTestId('zoom').textContent())).toBeGreaterThanOrEqual(3)
    await panIntoView(page, HOLE)
    const t3 = await readTransform(page)
    expect(t3.s / t1.s).toBeGreaterThanOrEqual(3)

    // p1 survives the zoom + pan untouched, and the same hole tapped at 3×
    // lands on the same normalized point as p2.
    await tapNormalized(page, HOLE)
    pts = await pendingPoints(page)
    expect(pts).toHaveLength(2)
    expectNear(pts[0], HOLE)
    expectNear(pts[1], HOLE)
  })

  test('two taps → reading → Enter → name → Enter saves; canvas gets focus back (M4 b2, b6, b7)', async ({page}) => {
    await openFace(page)
    await page.getByTestId('kind-diameter').click()
    await page.getByTestId('tolerance').fill('0.05')

    await tapNormalized(page, {x: 0.2, y: 0.5})
    expect(await pendingPoints(page)).toHaveLength(1)
    await tapNormalized(page, {x: 0.8, y: 0.5})
    expect(await pendingPoints(page)).toHaveLength(2)
    await expect(page.getByTestId('reading')).toBeFocused()
    await expect(page.getByTestId('reading')).toHaveAttribute('inputmode', 'decimal')
    await expect(page.getByTestId('reading')).toHaveAttribute('enterkeyhint', 'next')
    await expect(page.getByTestId('reading-units')).toHaveText('mm')

    await page.keyboard.type('12.34')
    await page.keyboard.press('Enter')
    await expect(page.getByTestId('name')).toBeFocused()
    await expect(page.getByTestId('name')).toHaveAttribute('enterkeyhint', 'done')
    await expect(page.getByTestId('name')).toHaveAttribute('autocapitalize', 'none')
    await page.keyboard.type('overall_l')
    await expect(page.getByTestId('save')).toBeEnabled()
    await page.keyboard.press('Enter')

    await expect(page.getByTestId('dimension-count')).toHaveText('1')
    await expect(page.getByTestId('reading')).toHaveValue('')
    await expect(page.getByTestId('name')).toHaveValue('')
    await expect(page.getByTestId('pending-points')).toHaveText('')
    await expect(page.getByTestId('kind-diameter')).toHaveAttribute('aria-pressed', 'true')
    await expect(page.getByTestId('tolerance')).toHaveValue('0.05')
    await expect(page.getByTestId('annotate-canvas')).toBeFocused()

    // Store round trip: the dimension is drawn/listed after a reload, and
    // the tolerance just used is now the part-units default.
    await page.reload()
    await expect(page.getByTestId('dimension-count')).toHaveText('1')
    await expect(page.getByTestId('tolerance')).toHaveValue('0.05')
    await expect(page.getByTestId('kind-length')).toHaveAttribute('aria-pressed', 'true')
  })

  test('validation: bad reading, bad name and mm fractions show inline errors and disable Save (M4 b3, b4)', async ({page}) => {
    await openFace(page)
    await tapNormalized(page, {x: 0.2, y: 0.5})
    await tapNormalized(page, {x: 0.8, y: 0.5})

    await page.getByTestId('reading').fill('abc')
    await expect(page.getByTestId('reading-error')).toBeVisible()
    await page.getByTestId('name').fill('overall_l')
    await expect(page.getByTestId('save')).toBeDisabled()

    await page.getByTestId('reading').fill('12.34')
    await expect(page.getByTestId('reading-error')).toHaveCount(0)
    await expect(page.getByTestId('save')).toBeEnabled()

    await page.getByTestId('name').fill('Overall_L')
    await expect(page.getByTestId('name-error')).toBeVisible()
    await expect(page.getByTestId('name-error')).toHaveText('Use a–z, 0–9 and _ ; start with a letter')
    await expect(page.getByTestId('save')).toBeDisabled()

    await page.getByTestId('name').fill('pi')
    await expect(page.getByTestId('name-error')).toContainText('reserved')
    await expect(page.getByTestId('save')).toBeDisabled()

    // Suggestion chips fill the name (SPEC §6.2 order: defaults first when
    // no other face has names yet).
    const chips = page.getByTestId('name-chip')
    await expect(chips.first()).toHaveText('overall_l')
    await chips.first().click()
    await expect(page.getByTestId('name')).toHaveValue('overall_l')
    await expect(page.getByTestId('save')).toBeEnabled()

    await page.getByTestId('reading').fill('1 3/8')
    await expect(page.getByTestId('reading-error')).toHaveText('Fractions only work in inches')
    await expect(page.getByTestId('save')).toBeDisabled()
  })

  test('reload mid-entry keeps the saved dimension and drops the half-typed one (M2 b4)', async ({page}) => {
    await openFace(page)
    await saveDimension(page, {x: 0.2, y: 0.5}, {x: 0.8, y: 0.5}, '42.18', 'overall_l')
    await expect(page.getByTestId('dimension-count')).toHaveText('1')

    await tapNormalized(page, {x: 0.55, y: 0.2})
    await tapNormalized(page, {x: 0.55, y: 0.8})
    await expect(page.getByTestId('reading')).toBeFocused()
    await page.keyboard.type('6.5')
    expect(await pendingPoints(page)).toHaveLength(2)

    await page.reload()
    await expect(page.getByTestId('dimension-count')).toHaveText('1')
    await expect(page.getByTestId('reading')).toHaveValue('')
    await expect(page.getByTestId('pending-points')).toHaveText('')
  })

  test('tapping an existing dimension selects it for edit; Delete removes it (M4 b8)', async ({page}) => {
    await openFace(page)
    await saveDimension(page, {x: 0.2, y: 0.5}, {x: 0.8, y: 0.5}, '42.18', 'overall_l')
    await expect(page.getByTestId('dimension-count')).toHaveText('1')
    await expect(page.getByTestId('delete')).toHaveCount(0)

    // Tap the middle of the saved line.
    await tapNormalized(page, {x: 0.5, y: 0.5})
    await expect(page.getByTestId('delete')).toBeVisible()
    await expect(page.getByTestId('reading')).toHaveValue('42.18')
    await expect(page.getByTestId('name')).toHaveValue('overall_l')
    const pts = await pendingPoints(page)
    expect(pts).toHaveLength(2)
    expectNear(pts[0], {x: 0.2, y: 0.5})
    expectNear(pts[1], {x: 0.8, y: 0.5})

    // Edit round trip: change the reading, Update, reselect, see the new value.
    await page.getByTestId('reading').fill('42.20')
    await page.getByTestId('save').click()
    await expect(page.getByTestId('dimension-count')).toHaveText('1')
    await expect(page.getByTestId('delete')).toHaveCount(0)
    await tapNormalized(page, {x: 0.5, y: 0.5})
    await expect(page.getByTestId('reading')).toHaveValue('42.2')

    await page.getByTestId('delete').click()
    await expect(page.getByTestId('dimension-count')).toHaveText('0')
    await expect(page.getByTestId('delete')).toHaveCount(0)
    await expect(page.getByTestId('pending-points')).toHaveText('')

    await page.reload()
    await expect(page.getByTestId('dimension-count')).toHaveText('0')
  })

  test('A1: dragging a saved handle moves that point, persists at once, and survives a reload (§8a A1)', async ({page}) => {
    await openFace(page)
    await saveDimension(page, {x: 0.2, y: 0.5}, {x: 0.8, y: 0.5}, '42.18', 'overall_l')
    await expect(page.getByTestId('dimension-count')).toHaveText('1')
    let dims = await dimensionPoints(page)
    expect(dims).toHaveLength(1)
    const id = dims[0].id
    expectNear(dims[0].p1, {x: 0.2, y: 0.5})
    expectNear(dims[0].p2, {x: 0.8, y: 0.5})

    // Grab p1 exactly (no selection first) and drag by a known screen delta.
    const t = await readTransform(page)
    const p1 = screenOf(t, {x: 0.2, y: 0.5})
    expect(insideBox(t, p1)).toBe(true)
    await dragFrom(page, p1, 40, 25)
    const d = normalizedDelta(t, 40, 25)
    const moved = {x: 0.2 + d.x, y: 0.5 + d.y}
    await waitForStored(page, id, moved, {x: 0.8, y: 0.5})

    // Nothing was selected by the drag and no Save was needed.
    await expect(page.getByTestId('delete')).toHaveCount(0)
    await expect(page.getByTestId('pending-points')).toHaveText('')

    await page.reload()
    await expect(page.getByTestId('dimension-count')).toHaveText('1')
    dims = await dimensionPoints(page)
    expect(dims).toHaveLength(1)
    expect(dims[0].id).toBe(id)
    expectNear(dims[0].p1, moved)
    expectNear(dims[0].p2, {x: 0.8, y: 0.5})
  })

  test('A1: dragging a saved line body moves both points by the delta; a tap on it still selects (§8a A1)', async ({page}) => {
    await openFace(page)
    await saveDimension(page, {x: 0.2, y: 0.5}, {x: 0.8, y: 0.5}, '42.18', 'overall_l')
    await expect(page.getByTestId('dimension-count')).toHaveText('1')
    const id = (await dimensionPoints(page))[0].id

    // Grab the middle of the line — 22 px handle radius is far from x=0.5.
    const t = await readTransform(page)
    const mid = screenOf(t, {x: 0.5, y: 0.5})
    expect(insideBox(t, mid)).toBe(true)
    await dragFrom(page, mid, -30, 20)
    const d = normalizedDelta(t, -30, 20)
    await expect(page.getByTestId('delete')).toHaveCount(0)
    await waitForStored(page, id, {x: 0.2 + d.x, y: 0.5 + d.y}, {x: 0.8 + d.x, y: 0.5 + d.y})

    await page.reload()
    await expect(page.getByTestId('dimension-count')).toHaveText('1')
    const dims = await dimensionPoints(page)
    expect(dims).toHaveLength(1)
    expectNear(dims[0].p1, {x: 0.2 + d.x, y: 0.5 + d.y})
    expectNear(dims[0].p2, {x: 0.8 + d.x, y: 0.5 + d.y})
    // Both moved together: same length and angle.
    expect(dims[0].p2[0] - dims[0].p1[0]).toBeCloseTo(0.6, 3)
    expect(dims[0].p2[1] - dims[0].p1[1]).toBeCloseTo(0, 3)

    // A tap (no movement) on the moved body selects it for edit, as before.
    await tapNormalized(page, {x: 0.5 + d.x, y: 0.5 + d.y})
    await expect(page.getByTestId('delete')).toBeVisible()
    await expect(page.getByTestId('reading')).toHaveValue('42.18')
    await expect(page.getByTestId('name')).toHaveValue('overall_l')
  })
})

// SPEC §8a A6: when p2 lands the view fits the pair; Save/Clear bring the
// view back unless the user moved it. Reduced motion makes the 160 ms tween
// instant, so every state below is a plain attribute wait.
test.describe('annotate — SPEC §8a A6 (fit the view to the dimension)', () => {
  // Two taps 60 px apart on screen at the fit scale, on a horizontal line
  // through the middle of the image; returns the pre-tap transform.
  async function placePair(page) {
    await page.emulateMedia({reducedMotion: 'reduce'})
    const t0 = await readTransform(page)
    await expect(page.getByTestId('annotate-canvas')).toHaveAttribute('data-autofit', 'none')
    const half = 30 / (t0.w * t0.s) // 30 screen px in normalized x
    await tapNormalized(page, {x: 0.5 - half, y: 0.45})
    await tapNormalized(page, {x: 0.5 + half, y: 0.45})
    await expect(page.getByTestId('annotate-canvas')).toHaveAttribute('data-autofit', 'fitted')
    await expect(page.getByTestId('reading')).toBeFocused()
    return t0
  }

  function expectTransformNear(actual, expected) {
    expect(Math.abs(actual.s - expected.s)).toBeLessThan(0.01)
    expect(Math.abs(actual.tx - expected.tx)).toBeLessThan(0.01)
    expect(Math.abs(actual.ty - expected.ty)).toBeLessThan(0.01)
  }

  test('two taps 60 px apart zoom the view onto the pair with ≥ 10 % margin', async ({page}) => {
    await openFace(page)
    const t0 = await placePair(page)
    const t1 = await readTransform(page)
    expect(t1.s).toBeGreaterThan(t0.s)
    expect(Number(await page.getByTestId('zoom').textContent())).toBeGreaterThan(1)
    const pts = await pendingPoints(page)
    expect(pts).toHaveLength(2)
    for (const [x, y] of pts) {
      const p = screenOf(t1, {x, y})
      expect(p.x).toBeGreaterThanOrEqual(t1.box.x + 0.1 * t1.box.width)
      expect(p.x).toBeLessThanOrEqual(t1.box.x + 0.9 * t1.box.width)
      expect(p.y).toBeGreaterThanOrEqual(t1.box.y + 0.1 * t1.box.height)
      expect(p.y).toBeLessThanOrEqual(t1.box.y + 0.9 * t1.box.height)
    }
  })

  test('Save brings the view back to where it was before the fit', async ({page}) => {
    await openFace(page)
    const t0 = await placePair(page)
    await page.keyboard.type('12.34')
    await page.keyboard.press('Enter')
    await expect(page.getByTestId('name')).toBeFocused()
    await page.keyboard.type('overall_l')
    await page.keyboard.press('Enter')
    await expect(page.getByTestId('dimension-count')).toHaveText('1')
    await expect(page.getByTestId('annotate-canvas')).toHaveAttribute('data-autofit', 'none')
    expectTransformNear(await readTransform(page), t0)
    await expect(page.getByTestId('zoom')).toHaveText('1.00')
    await expect(page.getByTestId('annotate-live')).toHaveText('Dimension saved: overall_l 12.34 mm')
  })

  test('a zoom-in between p2 and Save cancels the auto-fit: the view stays where the user put it', async ({page}) => {
    await openFace(page)
    const t0 = await placePair(page)
    await page.getByTestId('zoom-in').click()
    await expect(page.getByTestId('annotate-canvas')).toHaveAttribute('data-autofit', 'touched')
    const moved = await readTransform(page)
    expect(moved.s).toBeGreaterThan(t0.s)
    await page.getByTestId('reading').fill('12.34')
    await page.getByTestId('name').fill('overall_l')
    await page.getByTestId('save').click()
    await expect(page.getByTestId('dimension-count')).toHaveText('1')
    await expect(page.getByTestId('annotate-canvas')).toHaveAttribute('data-autofit', 'none')
    const after = await readTransform(page)
    expect(Math.abs(after.s - moved.s)).toBeLessThan(0.01)
    expect(Math.abs(after.s - t0.s)).toBeGreaterThan(0.01)
  })
})

// SPEC §8a A5: edge snap on `top.jpg` (fixtures/README.md): the bar spans
// x 0.17–0.81 and y 0.35–0.55 of the oriented 1600×1200 image, with the
// darker hole (centre 0.30, 0.45) inside it. The tap is still a sketch
// mark; snapping only moves it onto the visible edge. Reduced motion makes
// the A6 fit instant and skips the snap ring, so every state is a plain
// attribute wait.
test.describe('annotate — SPEC §8a A5 (edge snap)', () => {
  const BAR = {left: 0.17, right: 0.81}
  const SNAP_TOL = 0.004 // SPEC A5 bullet 6; the 1024-px patch resolves ~0.001

  async function openTopFace(page) {
    await page.emulateMedia({reducedMotion: 'reduce'})
    await page.goto('/')
    await page.getByTestId('new-part').click()
    await page.getByTestId('part-name').fill('Hinge pin')
    await page.getByTestId('part-create').click()
    await page.waitForURL(/#\/parts\/[^/]+$/)
    const partId = page.url().match(/#\/parts\/([^/]+)$/)[1]
    await page.goto(`/#/parts/${partId}/capture`)
    await page.setInputFiles('[data-testid=capture-file-top]', topJpg)
    await page.waitForURL(/#\/parts\/[^/]+\/faces\/[^/]+$/)
    const faceId = page.url().match(/\/faces\/([^/]+)$/)[1]
    await expect(page.locator('.shell-title')).toHaveText('Top · Hinge pin')
    await expect(page.getByTestId('annotate-canvas')).toHaveAttribute('data-image-size', '1600x1200')
    await expect(page.getByTestId('annotate-canvas')).toHaveAttribute('data-snap', 'on')
    return {partId, faceId}
  }

  function expectSnapped(actual, expected) {
    expect(Math.abs(actual[0] - expected.x)).toBeLessThan(SNAP_TOL)
    expect(Math.abs(actual[1] - expected.y)).toBeLessThan(SNAP_TOL)
  }

  test('on by default: a tap 12 px inside the left edge lands on the edge (snapPoint)', async ({page}) => {
    await openTopFace(page)
    const t = await readTransform(page)
    const edge = screenOf(t, {x: BAR.left, y: 0.45})
    expect(insideBox(t, edge)).toBe(true)
    await page.mouse.click(edge.x + 12, edge.y)
    const pts = await pendingPoints(page)
    expect(pts).toHaveLength(1)
    expect(Math.abs(pts[0][0] - BAR.left)).toBeLessThan(SNAP_TOL)
    await expect(page.getByTestId('annotate-canvas')).toHaveAttribute('data-snapped', 'true,false')
  })

  test('two rough taps either side of the bar land on its two edges (snapPair)', async ({page}) => {
    await openTopFace(page)
    await tapNormalized(page, {x: 0.15, y: 0.45})
    await tapNormalized(page, {x: 0.83, y: 0.45})
    const pts = await pendingPoints(page)
    expect(pts).toHaveLength(2)
    expectSnapped(pts[0], {x: BAR.left, y: 0.45})
    expectSnapped(pts[1], {x: BAR.right, y: 0.45})
    await expect(page.getByTestId('annotate-canvas')).toHaveAttribute('data-snapped', 'true,true')
    // The rest of the flow is untouched: p2 still fits the view and focuses
    // the reading.
    await expect(page.getByTestId('annotate-canvas')).toHaveAttribute('data-autofit', 'fitted')
    await expect(page.getByTestId('reading')).toBeFocused()
  })

  test('with the Snap pill off, the same taps are stored as tapped', async ({page}) => {
    await openTopFace(page)
    await setSnap(page, false)
    await tapNormalized(page, {x: 0.15, y: 0.45})
    await tapNormalized(page, {x: 0.83, y: 0.45})
    const pts = await pendingPoints(page)
    expect(pts).toHaveLength(2)
    expectSnapped(pts[0], {x: 0.15, y: 0.45})
    expectSnapped(pts[1], {x: 0.83, y: 0.45})
    await expect(page.getByTestId('annotate-canvas')).toHaveAttribute('data-snapped', 'false,false')
  })

  test('the pill state survives a reload and is the Settings row\'s field', async ({page}) => {
    const {partId, faceId} = await openTopFace(page)
    await setSnap(page, false)
    await page.reload()
    await expect(page.getByTestId('snap-toggle')).toHaveAttribute('aria-pressed', 'false')
    await expect(page.getByTestId('annotate-canvas')).toHaveAttribute('data-snap', 'off')

    // Settings shows the same field; flipping it there shows on the canvas.
    await page.goto('/#/settings')
    const row = page.getByTestId('snap-setting-toggle')
    await expect(row).not.toBeChecked()
    await row.click()
    await expect(row).toBeChecked()
    await page.goto(`/#/parts/${partId}/faces/${faceId}`)
    await expect(page.getByTestId('annotate-canvas')).toHaveAttribute('data-snap', 'on')
    await expect(page.getByTestId('snap-toggle')).toHaveAttribute('aria-pressed', 'true')
  })

  test('dragging a snapped handle moves it by the drag; a drag never re-snaps', async ({page}) => {
    await openTopFace(page)
    await tapNormalized(page, {x: 0.15, y: 0.45})
    let pts = await pendingPoints(page)
    expectSnapped(pts[0], {x: BAR.left, y: 0.45})
    const t = await readTransform(page)
    const handle = screenOf(t, {x: pts[0][0], y: pts[0][1]})
    // 20 px further into the bar — well inside the snap window, so a
    // re-snap would pull it straight back onto the edge.
    await dragFrom(page, handle, 20, 0)
    const d = normalizedDelta(t, 20, 0)
    const moved = {x: pts[0][0] + d.x, y: pts[0][1] + d.y}
    pts = await pendingPoints(page)
    expect(pts).toHaveLength(1)
    expectSnapped(pts[0], moved)
    await expect(page.getByTestId('annotate-canvas')).toHaveAttribute('data-snapped', 'false,false')

    // The second tap's snapPair snaps p2 but leaves the dragged p1 alone.
    await tapNormalized(page, {x: 0.83, y: 0.45})
    pts = await pendingPoints(page)
    expect(pts).toHaveLength(2)
    expectSnapped(pts[0], moved)
    expectSnapped(pts[1], {x: BAR.right, y: 0.45})
    await expect(page.getByTestId('annotate-canvas')).toHaveAttribute('data-snapped', 'false,true')
  })
})
