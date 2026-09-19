// scripts/demo-tour.mjs — record a demo video of the golden path with a
// visible cursor, subtitles and human pacing.
//
//   ASDF_NODEJS_VERSION=22.16.0 npm run dev            # or vite preview
//   node scripts/demo-tour.mjs --rehearse              # verify every selector
//   node scripts/demo-tour.mjs [outDir] [baseURL]      # record
//
// Phone portrait (the SPEC's 390×844) because that is the product: a phone
// in one hand, a caliper in the other. Motion is NOT reduced here — the
// A16 page pushes, the A6 fit tween and the polish-pass press/release are
// the point of the video. Seeds through the real UI like screenshot-tour,
// using the data-testid contract in docs/testids.md.
import {chromium} from 'playwright'
import fs from 'node:fs'
import path from 'node:path'

const positional = process.argv.filter(a => !a.startsWith('--'))
const outDir = positional[2] || 'docs/demo'
const baseURL = positional[3] || 'http://localhost:3000'
const REHEARSE = process.argv.includes('--rehearse')
const OUTPUT_NAME = 'snapkin-demo.webm'
const viewport = {width: 390, height: 844}

// The fixture's bar edges (e2e/specs/annotate.spec.js): `top.jpg` is a
// 1600×1200 synthetic part whose bar spans 0.17 → 0.81 normalized.
const BAR = {left: 0.17, right: 0.81, y: 0.45}

// ── overlays ──────────────────────────────────────────────────────────
// Both carry a `view-transition-name`, which lifts them OUT of the root
// snapshot during the app's page pushes (Motion.res) — otherwise the old
// screen's snapshot would slide away carrying a second, ghost cursor.
// Unique names, one element each: two elements sharing a name would reject
// the transition's `ready` and turn every push into a cut.
const injectOverlays = async page => {
  await page.evaluate(() => {
    if (!document.getElementById('demo-cursor')) {
      const cursor = document.createElement('div')
      cursor.id = 'demo-cursor'
      cursor.innerHTML = `<svg width="26" height="26" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M5 3L19 12L12 13L9 20L5 3Z" fill="white" stroke="black" stroke-width="1.5" stroke-linejoin="round"/>
      </svg>`
      cursor.style.cssText = `position: fixed; z-index: 2147483647; pointer-events: none;
        width: 26px; height: 26px; left: -50px; top: -50px;
        view-transition-name: demo-cursor;
        filter: drop-shadow(0 1px 3px rgba(0,0,0,0.5));`
      document.body.appendChild(cursor)
      addEventListener('mousemove', e => {
        cursor.style.left = e.clientX + 'px'
        cursor.style.top = e.clientY + 'px'
      })
    }
    if (!document.getElementById('demo-subtitle')) {
      const bar = document.createElement('div')
      bar.id = 'demo-subtitle'
      bar.style.cssText = `position: fixed; left: 12px; right: 12px; bottom: 20px;
        z-index: 2147483646; pointer-events: none; opacity: 0;
        padding: 10px 16px; border-radius: 999px; text-align: center;
        background: rgba(0,0,0,0.82); color: #fff;
        font: 500 15px/1.35 -apple-system, "SF Pro Text", system-ui, sans-serif;
        letter-spacing: 0.2px; text-wrap: balance;
        view-transition-name: demo-subtitle;
        transition: opacity 260ms ease;`
      document.body.appendChild(bar)
    }
  })
}

const subtitle = async (page, text, hold = 900) => {
  await page.evaluate(t => {
    const bar = document.getElementById('demo-subtitle')
    if (!bar) return
    if (t) bar.textContent = t
    bar.style.opacity = t ? '1' : '0'
  }, text)
  await page.waitForTimeout(text ? hold : 320)
}

// ── interaction helpers ───────────────────────────────────────────────
// Both phases walk the SAME route and perform the same actions — rehearsal
// has to click through to reach the later screens at all. `RECORD` only
// decides whether each action is dressed: cursor travel, dwell, subtitles
// and pans. So a rehearsal pass proves every selector on every screen.
let RECORD = true
const loc = (page, target) => (typeof target === 'string' ? page.locator(target).first() : target)

async function ensureVisible(page, target, label) {
  const el = loc(page, target)
  if (await el.isVisible().catch(() => false)) {
    console.log(`  ok   ${label}`)
    return true
  }
  console.error(`  FAIL ${label} — ${typeof target === 'string' ? target : '(locator)'}`)
  const found = await page.evaluate(() =>
    Array.from(document.querySelectorAll('button, input, select, textarea, a, canvas'))
      .filter(el => el.offsetParent !== null || el.tagName === 'CANVAS')
      .map(el => `${el.tagName}[${el.type || ''}]{${el.dataset.testid || ''}} "${(el.textContent || '').trim().slice(0, 30)}"`)
      .join('\n    '),
  )
  console.error('    visible:\n    ' + found)
  return false
}

async function moveTo(page, target, label) {
  const el = loc(page, target)
  if (!(await el.isVisible().catch(() => false))) throw new Error(`moveTo: "${label}" not visible`)
  await el.scrollIntoViewIfNeeded()
  if (!RECORD) return null
  await page.waitForTimeout(220)
  const box = await el.boundingBox()
  if (!box) throw new Error(`moveTo: "${label}" has no box`)
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2, {steps: 14})
  await page.waitForTimeout(340)
  return box
}

// The one click helper: verifies, travels (recording only), clicks, settles.
async function moveAndClick(page, target, label, after = 900) {
  const okEl = await ensureVisible(page, target, label)
  if (!okEl) throw new Error(`click: "${label}" not visible`)
  await moveTo(page, target, label)
  await loc(page, target).click()
  await page.waitForTimeout(RECORD ? after : 120)
}

async function typeSlowly(page, target, text, label, delay = 42) {
  await moveAndClick(page, target, label, 260)
  const el = loc(page, target)
  await el.fill('')
  if (!RECORD) return el.fill(text)
  await el.pressSequentially(text, {delay})
  await page.waitForTimeout(600)
}

// Pan the cursor across a set of elements so the eye is led around a screen.
async function pan(page, selector, max = 5, dwell = 520) {
  if (!RECORD) return
  const els = await page.locator(selector).all()
  for (const el of els.slice(0, max)) {
    const box = await el.boundingBox().catch(() => null)
    if (!box || box.y > viewport.height - 60) continue
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2, {steps: 12})
    await page.waitForTimeout(dwell)
  }
}

const settled = page =>
  page.waitForFunction(
    () => document.querySelector('[data-testid="annotate-canvas"]')?.getAttribute('data-autofit') !== 'fitting',
  )

// The canvas element exists before its bitmap is decoded, and a tap on a
// photo-less canvas is silently ignored — the first tap vanished and the
// pair never formed. `data-image-size` is the readiness signal (it is what
// e2e/specs/annotate.spec.js waits on); `data-autofit` is not, because it
// reads `none` all through the load.
const imageReady = page =>
  page.waitForFunction(() =>
    /^[1-9]\d*x[1-9]\d*$/.test(
      document.querySelector('[data-testid="annotate-canvas"]')?.getAttribute('data-image-size') || '',
    ),
  )


// Canvas geometry (docs/testids.md "Annotate"): screen = box + n * size * scale + t.
// `data-transform` already reports the end state while `data-autofit` is
// `fitting`, and a pointerdown completes the tween first — so a tap computed
// from the attribute lands where it says even mid-animation.
// `want` is the number of pending points the tap should produce. The stage
// finishes sizing a beat after the bitmap decodes (its height tracks
// `--vv-height`), and a tap computed against the old box misses the image
// and is swallowed — so recompute and retry rather than record a demo where
// the first edge silently never landed.
async function tapNormalized(page, n, label, want) {
  const canvas = page.getByTestId('annotate-canvas')
  for (let attempt = 1; attempt <= 4; attempt++) {
    const [s, tx, ty] = (await canvas.getAttribute('data-transform')).split(',').map(Number)
    const [w, h] = (await canvas.getAttribute('data-image-size')).split('x').map(Number)
    const box = await canvas.boundingBox()
    const p = {x: box.x + n.x * w * s + tx, y: box.y + n.y * h * s + ty}
    if (p.x < box.x + 4 || p.x > box.x + box.width - 4 || p.y < box.y + 4 || p.y > box.y + box.height - 4) {
      throw new Error(`tap "${label}": the point falls outside the canvas`)
    }
    if (RECORD && attempt === 1) {
      await page.mouse.move(p.x, p.y, {steps: 16})
      await page.waitForTimeout(420)
    }
    await page.mouse.click(p.x, p.y)
    try {
      await page.waitForFunction(
        w =>
          (document.querySelector('[data-testid="pending-points"]').textContent || '')
            .split(';')
            .filter(Boolean).length === w,
        want,
        {timeout: 1500},
      )
      await page.waitForTimeout(RECORD ? 700 : 80)
      return
    } catch {
      console.warn(`  retrying tap "${label}" (attempt ${attempt} did not register)`)
      await page.waitForTimeout(400)
    }
  }
  throw new Error(`tap "${label}" never registered`)
}

// ── the flow ──────────────────────────────────────────────────────────
// One route for both phases: rehearsal walks it and only checks that each
// selector resolves, recording walks it with the cursor, subtitles and pauses.
async function run(page) {
  const record = RECORD
  const say = record ? (t, hold) => subtitle(page, t, hold) : async () => {}
  const beat = record ? ms => page.waitForTimeout(ms) : async () => {}

  await page.goto(`${baseURL}/#/`)
  await page.waitForSelector('[data-testid="new-part"]')
  await injectOverlays(page)
  await beat(700)
  await say('Snapkin — measure a part with calipers, keep the numbers', 2600)
  await say('')

  // 1. Create the part.
  await say('Start with a part', 1400)
  await moveAndClick(page, '[data-testid="new-part"]', 'New part')
  await say('')

  const units = page.getByRole('group', {name: 'Units'})
  await typeSlowly(page, '[data-testid="part-name"]', 'Norcold freezer hinge pin', 'Name field')
  // Flip the units segment and back — the thumb glides, the labels follow.
  await moveAndClick(page, units.getByRole('button', {name: 'in', exact: true}), 'Units: in', 700)
  await moveAndClick(page, units.getByRole('button', {name: 'mm', exact: true}), 'Units: mm', 900)
  await moveAndClick(page, '[data-testid="part-create"]', 'Create')

  // 2. Capture a face.
  await page.waitForSelector('[data-testid="capture-face"]')
  await injectOverlays(page)
  await say('A part is a set of photographed faces', 2000)
  await say('')
  await moveAndClick(page, '[data-testid="capture-face"]', 'Capture card')

  await page.waitForSelector('[data-testid="shutter"]')
  await injectOverlays(page)
  await say('Pick the face, then shoot it', 1800)
  await ensureVisible(page, '[data-testid="capture-chip-top"]', 'Top kind card')
  await pan(page, '[data-testid^="capture-chip-"]', 4, 460)
  await say('')
  // The real path: the shutter is a <label> over the capture input, so the
  // click opens a file chooser Playwright answers with the fixture.
  const [chooser] = await Promise.all([
    page.waitForEvent('filechooser'),
    moveAndClick(page, '[data-testid="shutter"]', 'Shutter', 400),
  ])
  await chooser.setFiles(path.resolve('fixtures/hinge_pin/top.jpg'))

  // 3. Annotate: two taps, a reading, a name.
  await page.waitForSelector('[data-testid="annotate-canvas"]')
  await imageReady(page)
  await settled(page)
  await injectOverlays(page)
  await beat(900)
  await say('The photo is never measured — it is a labelled sketch', 2600)
  await say('Tap the two edges…', 1500)
  await say('')
  await ensureVisible(page, '[data-testid="annotate-canvas"]', 'Canvas')
  await tapNormalized(page, {x: BAR.left, y: BAR.y}, 'first edge', 1)
  await tapNormalized(page, {x: BAR.right, y: BAR.y}, 'second edge', 2)
  await settled(page)
  await beat(600)
  await say('…then type what the caliper says', 1600)
  await say('')
  await typeSlowly(page, '[data-testid="reading"]', '42.18', 'Reading field')
  await say('Name it the way Fusion will', 1500)
  await say('')
  await moveAndClick(page, page.getByTestId('name-chip').first(), 'Name chip', 700)
  await moveAndClick(page, '[data-testid="save"]', 'Save dimension')
  await settled(page)
  await beat(800)
  await say('Saved — drawn on the photo and listed below', 2400)
  await say('')
  if (record) {
    await page.evaluate(() => document.querySelector('.shell')?.scrollTo({top: 600, behavior: 'smooth'}))
    await beat(1600)
    await pan(page, '[data-testid="dimension-row"]', 2, 700)
    await beat(700)
    await page.evaluate(() => document.querySelector('.shell')?.scrollTo({top: 0, behavior: 'smooth'}))
    await beat(1200)
  }
  await ensureVisible(page, '[data-testid="dimension-row"]', 'Saved dimension row')

  // 4. Back to the part: the reconciled feature list, then export.
  await moveAndClick(page, '.shell-back', 'Back', 1200)
  await page.waitForSelector('[data-testid="export"]')
  await injectOverlays(page)
  await say('Every face, every dimension, in one place', 2200)
  await say('')
  await ensureVisible(page, '[data-testid="feature-row"]', 'Feature row')
  await pan(page, '[data-testid^="face-"], [data-testid="feature-row"]', 4, 560)
  await say('Export a dimensioned PNG per face — and features.json for Fusion 360', 2600)
  await say('')
  const download = page.waitForEvent('download', {timeout: 20000}).catch(() => null)
  await moveAndClick(page, '[data-testid="export"]', 'Export', 2200)
  const file = await download
  console.log(file ? `  export produced: ${file.suggestedFilename()}` : '  WARNING: export produced no download')
  await say('Snapkin', 2400)
  await say('')
  await beat(900)
  return file != null
}

// ── main ──────────────────────────────────────────────────────────────
const browser = await chromium.launch()
const context = await browser.newContext({
  viewport,
  deviceScaleFactor: 2,
  isMobile: true,
  hasTouch: true,
  acceptDownloads: true,
  ...(REHEARSE ? {} : {recordVideo: {dir: outDir, size: viewport}}),
})
const page = await context.newPage()
page.on('pageerror', e => {
  // Motion.res rejects `ready` on an interrupted transition; that one is
  // expected and not a demo failure.
  if (!/Transition was skipped/.test(e.message)) console.error('  pageerror:', e.message)
})

let failed = false
try {
  RECORD = !REHEARSE
  if (REHEARSE) {
    console.log('rehearsing against', baseURL, '— walking the whole route, undressed\n')
    const ok = await run(page)
    console.log(ok ? '\nREHEARSAL PASSED — every step resolved' : '\nREHEARSAL FAILED — see above')
    failed = !ok
  } else {
    fs.mkdirSync(outDir, {recursive: true})
    await run(page)
  }
} catch (err) {
  console.error('DEMO ERROR:', err.message)
  failed = true
} finally {
  await context.close()
  const video = page.video()
  if (video) {
    const src = await video.path()
    const dest = path.join(outDir, OUTPUT_NAME)
    try {
      fs.copyFileSync(src, dest)
      fs.rmSync(src, {force: true})
      console.log('video:', dest, `(${(fs.statSync(dest).size / 1e6).toFixed(1)} MB)`)
    } catch (e) {
      console.error('could not copy the video from', src, '—', e.message)
    }
  }
  await browser.close()
}
process.exit(failed ? 1 : 0)
