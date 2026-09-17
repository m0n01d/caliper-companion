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

const optionFor = (page, path) => page.locator(`[data-testid="folder-option"][data-path="${path}"]`)

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
    // The app renders after its module loads; on a cold run the first Tab
    // could arrive before any control exists and land on <body>.
    await expect(page.getByTestId('part-row')).toHaveCount(1)
    await page.keyboard.press('Tab')
    const tag = await page.evaluate(() => document.activeElement?.tagName)
    expect(tag).not.toBe('BODY')
  })

  test('part page — buttons named, features list has real list/listitem roles, live region present, Tab reaches Back then content', async ({
    page,
  }) => {
    const partId = await createPart(page, 'A11y part')
    await page.goto(`/#/parts/${partId}/capture`)
    await page.setInputFiles('[data-testid="capture-file-top"]', FIXTURE_TOP)
    await expect(page).toHaveURL(/#\/parts\/[^/]+\/faces\/[^/]+\/?$/)

    // One dimension, so Part.res actually renders the features list (it's
    // plain text — "No dimensions captured yet." — until there's at least
    // one).
    await clickNormalizedPoint(page, 0.2, 0.5)
    await clickNormalizedPoint(page, 0.6, 0.5)
    await page.getByTestId('reading').fill('10.00')
    await page.getByTestId('reading').press('Enter')
    await page.getByTestId('name').fill('length')
    await page.getByTestId('name').press('Enter')

    await page.goto(`/#/parts/${partId}`)
    await expect(page.getByTestId('part-live')).toBeAttached()
    await expect(page.getByTestId('feature-row')).toHaveCount(1)

    // P2a (layout A, review-2026-09-17.md F5/§4 "Feature row"): the
    // features table became a role=list of role=listitem rows (no column
    // header row — the group header carries the unit instead). This is the
    // regression guard for that structure, not just "does the list exist".
    const list = page.getByTestId('features-list')
    await expect(list).toHaveAttribute('role', 'list')
    const rows = page.getByTestId('feature-row')
    await expect(rows).toHaveCount(1)
    for (const row of await rows.all()) {
      await expect(row).toHaveAttribute('role', 'listitem')
      const label = await row.getAttribute('aria-label')
      expect(label?.length ?? 0).toBeGreaterThan(0)
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
    await expect(backBtn).toBeVisible() // app rendered; see the root test's note
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
    await expect(backBtn).toBeVisible() // app rendered; see the root test's note
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

  // SPEC §8a A12a (review S7): the folder picker's options are real
  // <button role="option">s — Tab reaches them, `aria-selected` tells the
  // truth, and the selected one is focused when the picker opens.
  test('parts list — folder picker: options are role=option buttons, Tab-reachable, aria-selected truthful, the selected one focused on open', async ({
    page,
  }) => {
    await page.goto('/')
    await page.getByTestId('new-part').click()
    await page.getByTestId('part-folder-row').click()
    const options = page.getByTestId('folder-option')
    await expect(options).toHaveCount(1)
    await expect(options.first()).toBeFocused()
    await page.getByTestId('folder-new').click()
    await page.getByTestId('folder-new-name').fill('Miata')
    await page.getByTestId('folder-new-create').click()
    await expect(options).toHaveCount(2)
    await expect(options.nth(1)).toBeFocused()
    for (const option of await options.all()) {
      expect(await option.evaluate(el => el.tagName)).toBe('BUTTON')
      await expect(option).toHaveAttribute('role', 'option')
      const label = await option.getAttribute('aria-label')
      expect(label?.length ?? 0).toBeGreaterThan(0)
    }
    await expect(options.nth(0)).toHaveAttribute('aria-selected', 'false')
    await expect(options.nth(1)).toHaveAttribute('aria-selected', 'true')
    await expectEveryButtonNamed(page)

    // DOM order in the bar is Cancel → Done → the options, so two Tabs from
    // Cancel land on the first option; Space selects it.
    await page.getByTestId('folder-picker-cancel').focus()
    await page.keyboard.press('Tab')
    await expect(page.getByTestId('folder-picker-done')).toBeFocused()
    await page.keyboard.press('Tab')
    await expect(options.nth(0)).toBeFocused()
    await page.keyboard.press('Space')
    await expect(options.nth(0)).toHaveAttribute('aria-selected', 'true')
    await expect(options.nth(1)).toHaveAttribute('aria-selected', 'false')

    // Reopening focuses whichever option is selected, not always the first.
    await optionFor(page, 'Miata').click()
    await page.getByTestId('folder-picker-done').click()
    await expect(page.getByTestId('part-folder-row')).toBeFocused()
    await page.getByTestId('part-folder-row').click()
    await expect(optionFor(page, 'Miata')).toBeFocused()
  })

  test('parts list — rename autofocuses its draft input; deleting a part sends focus to New part', async ({
    page,
  }) => {
    await createPart(page, 'A11y rename part')
    await page.getByRole('button', {name: 'Back'}).click()
    await expect(page.getByTestId('part-row')).toHaveCount(1)

    // P2a (layout A): rename/delete only show once the bar's "Edit" text
    // action is tapped (review-2026-09-17.md P1) — no longer permanent
    // per-row icon buttons.
    await page.getByTestId('parts-edit').click()
    await page.getByTestId('part-rename').click()
    await expect(page.getByTestId('part-rename-input')).toBeFocused()
    await page.getByTestId('part-rename-cancel').click()

    await page.getByTestId('part-delete').click()
    await page.getByTestId('part-delete-confirm').click()
    await expect(page.getByTestId('part-row')).toHaveCount(0)
    await expect(page.getByTestId('new-part')).toBeFocused()
  })
})
