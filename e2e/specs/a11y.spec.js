// a11y.spec.js — design wave 3b accessibility sweep acceptance (DESIGN.md
// §9, docs/testids.md's `*-live`/`shutter` ids). On `#/`, a part page and
// the capture page: every icon-only button still has an accessible name
// (`getByRole('button')` all resolve to a non-empty name), the features
// table exposes real column headers despite its CSS grid layout
// (Part.css), each page's `aria-live="polite"` region is in the DOM, the
// create/rename inputs get focus when their editor opens, and a
// keyboard-only Tab pass reaches Back first (where the page has one), then
// moves forward into the page content — never gets stuck. Two more tests
// exercise the specific focus-management paths design wave 3b added
// (custom-face card autofocus, recapture-cancel returning focus to the
// shutter) directly, since nothing else in the suite touches them.
import {test, expect} from '@playwright/test'

const FIXTURE_TOP = 'fixtures/hinge_pin/top.jpg'

async function createPart(page, name) {
  await page.goto('/')
  await page.getByTestId('new-part').click()
  await page.getByTestId('part-name').fill(name)
  await page.getByTestId('part-create').click()
  await page.waitForURL(/#\/parts\/[^/]+\/?$/, {timeout: 10_000})
  return page.url().match(/#\/parts\/([^/?#]+)/)[1]
}

// Same shape as faces.spec.js's own helper: reads the canvas's live
// `data-transform`/`data-image-size` attributes to convert a normalized
// (nx, ny) into a screen click.
async function clickNormalizedPoint(page, nx, ny) {
  const canvas = page.getByTestId('annotate-canvas')
  const box = await canvas.boundingBox()
  if (!box) throw new Error('annotate-canvas has no bounding box (not visible?)')
  const raw = await canvas.getAttribute('data-transform')
  const [scale, tx, ty] = (raw ?? '1,0,0').split(',').map(Number)
  const [imgW, imgH] = ((await canvas.getAttribute('data-image-size')) ?? '1x1').split('x').map(Number)
  await page.mouse.click(box.x + tx + nx * imgW * scale, box.y + ty + ny * imgH * scale)
}

// DESIGN.md §9 "Every icon-only control has an aria-label": every
// `role=button` element must resolve to a non-empty accessible name. This
// app never uses `aria-labelledby`, so `aria-label` (if present) else
// trimmed text content is the whole accessible-name computation that
// matters here — good enough to catch a control that lost its label,
// without pulling in a full a11y-tree API.
async function expectEveryButtonNamed(page) {
  const buttons = await page.getByRole('button').all()
  expect(buttons.length).toBeGreaterThan(0)
  for (const button of buttons) {
    const {name, html} = await button.evaluate(el => ({
      name: (el.getAttribute('aria-label') || el.textContent || '').trim(),
      html: el.outerHTML.slice(0, 120),
    }))
    expect(name.length, `button with no accessible name: ${html}`).toBeGreaterThan(0)
  }
}

test.describe('accessibility sweep (design wave 3b)', () => {
  test('#/ — buttons named, live region present, New part autofocuses the name field, Tab reaches a real control', async ({
    page,
  }) => {
    await page.goto('/')
    await expect(page.getByTestId('parts-live')).toBeAttached()

    await page.getByTestId('new-part').click()
    // DESIGN.md §9 "Focus management": "the inline create/rename editors
    // autofocus their input".
    await expect(page.getByTestId('part-name')).toBeFocused()
    await page.getByTestId('part-name').fill('A11y sweep part')
    await page.getByTestId('part-create').click()
    await expect(page).toHaveURL(/#\/parts\/[^/]+\/?$/)
    await page.getByRole('button', {name: 'Back'}).click()
    await expect(page.getByTestId('part-row')).toHaveCount(1)

    // The row's Rename/Delete icon buttons are on screen now too.
    await expectEveryButtonNamed(page)

    // Root has no back button (`PartsList.back = None` — Shell.res only
    // renders one when there's somewhere to go back to), so the first Tab
    // should land directly on a real, on-screen control, not fall through
    // to `<body>`. Reloaded first for a clean "first Tab" starting point —
    // see the longer comment in the part-page test below on why.
    await page.reload()
    await page.keyboard.press('Tab')
    const tag = await page.evaluate(() => document.activeElement?.tagName)
    expect(tag).not.toBe('BODY')
  })

  test('part page — buttons named, features table has real column headers, live region present, Tab reaches Back then content', async ({
    page,
  }) => {
    const partId = await createPart(page, 'A11y part')
    await page.goto(`/#/parts/${partId}/capture`)
    await page.setInputFiles('[data-testid="capture-file-top"]', FIXTURE_TOP)
    await expect(page).toHaveURL(/#\/parts\/[^/]+\/faces\/[^/]+\/?$/)

    // One dimension, so Part.res actually renders the `<table>` (it's plain
    // text — "No dimensions captured yet." — until there's at least one).
    await clickNormalizedPoint(page, 0.2, 0.5)
    await clickNormalizedPoint(page, 0.6, 0.5)
    await page.getByTestId('reading').fill('10.00')
    await page.getByTestId('reading').press('Enter')
    await page.getByTestId('name').fill('length')
    await page.getByTestId('name').press('Enter')

    await page.goto(`/#/parts/${partId}`)
    await expect(page.getByTestId('part-live')).toBeAttached()
    await expect(page.getByTestId('feature-row')).toHaveCount(1)

    // Part.css lays the table out as `display: grid` (so the name column
    // can shrink+ellipsis — see that file), which strips the implicit
    // table/row/cell roles the CSS Display spec normally computes from the
    // HTML tag. Part.res restores them explicitly; this is the regression
    // guard for that fix, not just "does a <table> exist".
    const table = page.locator('.features-table')
    await expect(table).toHaveAttribute('role', 'table')
    const headers = table.locator('[role="columnheader"]')
    await expect(headers).toHaveCount(4)
    for (const header of await headers.all()) {
      await expect(header).toHaveAttribute('scope', 'col')
    }

    await expectEveryButtonNamed(page)

    // A real reload, not another hash-only SPA transition: Chromium anchors
    // "first Tab" sequential-navigation search to the last interaction
    // point, which can survive a same-document route change even once
    // `document.activeElement` has fallen back to `<body>` (verified
    // against a throwaway script before writing this) — a browser/harness
    // quirk, not an app bug, and not what "Tab from the top" means anyway.
    // A full load is the one way to get a clean starting point, and it's
    // also the realistic case: a keyboard user arriving at this URL fresh.
    await page.reload()
    const backBtn = page.getByRole('button', {name: 'Back'})
    await page.keyboard.press('Tab')
    await expect(backBtn).toBeFocused()
    await page.keyboard.press('Tab')
    await expect(backBtn).not.toBeFocused()
    const tag = await page.evaluate(() => document.activeElement?.tagName)
    expect(tag).not.toBe('BODY')
  })

  test('capture page — buttons named, live region present, Tab reaches Back then content', async ({page}) => {
    const partId = await createPart(page, 'A11y capture part')
    await page.goto(`/#/parts/${partId}/capture`)
    await expect(page.getByTestId('capture-live')).toBeAttached()

    await expectEveryButtonNamed(page)

    // See the comment in the part-page test above for why this reload is
    // here (a clean "first Tab" starting point, not a same-document hop).
    await page.reload()
    const backBtn = page.getByRole('button', {name: 'Back'})
    await page.keyboard.press('Tab')
    await expect(backBtn).toBeFocused()
    await page.keyboard.press('Tab')
    await expect(backBtn).not.toBeFocused()
    const tag = await page.evaluate(() => document.activeElement?.tagName)
    expect(tag).not.toBe('BODY')
  })

  test('capture page — custom-face card autofocuses its name field; recapture Cancel returns focus to the shutter', async ({
    page,
  }) => {
    const partId = await createPart(page, 'A11y focus part')
    await page.goto(`/#/parts/${partId}/capture`)

    await page.getByTestId('custom-face').click()
    await expect(page.getByTestId('custom-face-label')).toBeFocused()
    await page.getByTestId('custom-face-cancel').click()
    await expect(page.getByTestId('custom-face-card')).toHaveCount(0)

    await page.setInputFiles('[data-testid="capture-file-top"]', FIXTURE_TOP)
    await expect(page).toHaveURL(/#\/parts\/[^/]+\/faces\/[^/]+\/?$/)

    await page.goto(`/#/parts/${partId}/capture`)
    await page.setInputFiles('[data-testid="capture-file-top"]', FIXTURE_TOP)
    await expect(page.getByTestId('recapture-confirm')).toBeVisible()
    await page.getByTestId('recapture-cancel').click()
    await expect(page.getByTestId('recapture-confirm')).toHaveCount(0)
    await expect(page.getByTestId('shutter')).toBeFocused()
  })

  test('parts list — rename autofocuses its draft input; deleting a part sends focus to New part', async ({
    page,
  }) => {
    await createPart(page, 'A11y rename part')
    await page.getByRole('button', {name: 'Back'}).click()
    await expect(page.getByTestId('part-row')).toHaveCount(1)

    await page.getByTestId('part-rename').click()
    await expect(page.getByTestId('part-rename-input')).toBeFocused()
    await page.getByTestId('part-rename-cancel').click()

    await page.getByTestId('part-delete').click()
    await page.getByTestId('part-delete-confirm').click()
    await expect(page.getByTestId('part-row')).toHaveCount(0)
    await expect(page.getByTestId('new-part')).toBeFocused()
  })
})
