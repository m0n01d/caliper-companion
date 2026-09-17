// parts.spec.js — SPEC M2 bullet 2/3 + M4 wedge toggle + M6 bullets 2-3
// acceptance: create → navigate → empty part screen, rename/delete round
// trips, the wedge-dongle toggle persisting, and the Debug CSV download.
//
// Each `test(...)` gets its own browser context from Playwright's default
// `page` fixture, so IndexedDB never leaks between tests — no explicit
// context setup needed (see shell.spec.js for the same assumption).
import {test, expect} from '@playwright/test'
import {readFile} from 'node:fs/promises'

test.describe('parts', () => {
  test('creating a part navigates to an empty part screen', async ({page}) => {
    await page.goto('/')
    await expect(page.getByTestId('parts-empty')).toBeVisible()

    await page.getByTestId('new-part').click()
    await page.getByTestId('part-name').fill('Hinge Pin')
    await page.getByTestId('part-units').selectOption('mm')
    await page.getByTestId('part-create').click()

    await expect(page).toHaveURL(/#\/parts\/.+/)
    await expect(page.locator('.shell-title')).toHaveText('Hinge Pin')
    // empty faces, empty features, timer not started
    await expect(page.getByTestId(/^face-/)).toHaveCount(0)
    await expect(page.getByTestId('capture-face')).toBeVisible()
    await expect(page.getByTestId('feature-row')).toHaveCount(0)
    await expect(page.getByTestId('warning-row')).toHaveCount(0)
    await expect(page.getByTestId('timer')).toHaveText('Timer starts at first capture')

    await page.getByRole('button', {name: 'Back'}).click()
    await expect(page.getByTestId('part-row')).toHaveCount(1)
    await expect(page.getByTestId('part-row')).toContainText('Hinge Pin')
  })

  test('rename persists after reload', async ({page}) => {
    await page.goto('/')
    await page.getByTestId('new-part').click()
    await page.getByTestId('part-name').fill('Original Name')
    await page.getByTestId('part-create').click()
    await expect(page).toHaveURL(/#\/parts\/.+/)
    await page.getByRole('button', {name: 'Back'}).click()

    // P2a (layout A): rename/delete live behind the bar's "Edit" text
    // action now, not as permanent per-row icon buttons.
    await page.getByTestId('parts-edit').click()
    await page.getByTestId('part-rename').click()
    await page.getByTestId('part-rename-input').fill('Renamed Part')
    await page.getByTestId('part-rename-save').click()
    await expect(page.getByTestId('part-row')).toContainText('Renamed Part')

    await page.reload()
    await expect(page.getByTestId('part-row')).toContainText('Renamed Part')
  })

  test('delete with confirm returns to the empty state', async ({page}) => {
    await page.goto('/')
    await page.getByTestId('new-part').click()
    await page.getByTestId('part-name').fill('Throwaway Part')
    await page.getByTestId('part-create').click()
    await expect(page).toHaveURL(/#\/parts\/.+/)
    await page.getByRole('button', {name: 'Back'}).click()
    await expect(page.getByTestId('part-row')).toHaveCount(1)

    // P2a (layout A): same "Edit" gate as the rename test above.
    await page.getByTestId('parts-edit').click()
    await page.getByTestId('part-delete').click()
    await page.getByTestId('part-delete-confirm').click()

    await expect(page.getByTestId('parts-empty')).toBeVisible()
    await expect(page.getByTestId('part-row')).toHaveCount(0)
  })

  test('settings wedge toggle persists after reload', async ({page}) => {
    await page.goto('/#/settings')
    const toggle = page.getByTestId('wedge-toggle')
    await expect(toggle).toBeVisible()
    await expect(toggle).not.toBeChecked()

    await toggle.click()
    await expect(toggle).toBeChecked()

    await page.reload()
    await expect(page.getByTestId('wedge-toggle')).toBeChecked()
  })

  test('debug CSV export downloads a file with the RFC-4180 header first', async ({page}) => {
    await page.goto('/#/debug')
    await expect(page.getByTestId('export-csv')).toBeVisible()

    const [download] = await Promise.all([
      page.waitForEvent('download'),
      page.getByTestId('export-csv').click(),
    ])

    expect(download.suggestedFilename()).toBe('caliper-timers.csv')
    const path = await download.path()
    const text = await readFile(path, 'utf8')
    const firstLine = text.split('\n')[0]
    expect(firstLine).toBe('partId,partName,startedAt,stoppedAt,handsOnSeconds')
  })
})

// SPEC §8a A10 — folders. The list groups parts into one inset section per
// folder (root first, never with a header), a search field filters by name
// or path, and the shared create/rename form's Folder field moves a part.
// Named parts per docs/design/a10-folders-review.md S7 so "search `bezel`
// filters to one" is a real assertion.
async function createPartIn(page, name, folder) {
  await page.goto('/')
  await page.getByTestId('new-part').click()
  await page.getByTestId('part-name').fill(name)
  if (folder !== undefined) {
    await page.getByTestId('part-path').fill(folder)
  }
  await page.getByTestId('part-create').click()
  await page.waitForURL(/#\/parts\/[^/]+\/?$/, {timeout: 10_000})
}

test.describe('parts — folders (SPEC §8a A10)', () => {
  test('sections with counts, root first and headerless; search filters; rename moves and re-sorts', async ({
    page,
  }) => {
    await createPartIn(page, 'Window switch bezel', 'Miata/Interior')
    // The Part page's Shell subtitle is the folder path (review B2).
    await expect(page.locator('.shell-subtitle')).toHaveText('Miata / Interior')
    await createPartIn(page, 'Door card clip', 'Miata/Interior')
    await createPartIn(page, 'Hinge pin')
    // Root: no subtitle at all.
    await expect(page.locator('.shell-subtitle')).toHaveCount(0)

    await page.goto('/')
    await expect(page.getByTestId('part-row')).toHaveCount(3)
    const sections = page.getByTestId('parts-section')
    await expect(sections).toHaveCount(2)
    // Root section first and headerless: exactly one header, the folder's.
    await expect(page.getByTestId('parts-section-header')).toHaveCount(1)
    await expect(page.getByTestId('parts-section-header')).toHaveText('Miata / Interior · 2')
    await expect(sections.nth(0).getByTestId('part-row')).toHaveCount(1)
    await expect(sections.nth(0)).toContainText('Hinge pin')
    await expect(sections.nth(1).getByTestId('part-row')).toHaveCount(2)

    // Search: live, case-insensitive, name or path; sections preserved.
    const search = page.getByTestId('parts-search')
    await expect(search).toHaveAttribute('type', 'search')
    await search.fill('bezel')
    await expect(page.getByTestId('part-row')).toHaveCount(1)
    await expect(page.getByTestId('part-row')).toContainText('Window switch bezel')
    await expect(page.getByTestId('parts-section-header')).toHaveText('Miata / Interior · 1')
    await search.fill('interior')
    await expect(page.getByTestId('part-row')).toHaveCount(2)
    await search.fill('zzz')
    await expect(page.getByTestId('part-row')).toHaveCount(0)
    await expect(page.getByTestId('parts-search-empty')).toHaveText('No parts match "zzz".')
    await page.getByTestId('parts-search-clear').click()
    await expect(search).toHaveValue('')
    await expect(search).toBeFocused()
    await expect(page.getByTestId('part-row')).toHaveCount(3)

    // Rename's Folder field moves the part; the root section disappears
    // and the moved part re-sorts to the top of its new section (S6).
    await page.getByTestId('parts-edit').click()
    await sections.nth(0).getByTestId('part-rename').click()
    await expect(page.getByTestId('part-rename-input')).toHaveValue('Hinge pin')
    await expect(page.getByTestId('part-path')).toHaveValue('')
    // The chips list the existing folders; tapping one fills the field.
    await expect(page.getByTestId('part-path-chip')).toHaveCount(1)
    await page.getByTestId('part-path-chip').click()
    await expect(page.getByTestId('part-path')).toHaveValue('Miata/Interior')
    await page.getByTestId('part-rename-save').click()
    await expect(page.getByTestId('parts-section')).toHaveCount(1)
    await expect(page.getByTestId('parts-section-header')).toHaveText('Miata / Interior · 3')
    await expect(page.getByTestId('part-row').first()).toContainText('Hinge pin')

    await page.reload()
    await expect(page.getByTestId('parts-section')).toHaveCount(1)
    await expect(page.getByTestId('parts-section-header')).toHaveText('Miata / Interior · 3')
    await expect(page.getByTestId('part-row').first()).toContainText('Hinge pin')
  })

  test('folder field: a//b normalises, ? is rejected inline, a different case snaps to the existing spelling', async ({
    page,
  }) => {
    // Review B1: doubled slashes normalise rather than reject.
    await createPartIn(page, 'Normalised', 'a//b')
    await expect(page.locator('.shell-subtitle')).toHaveText('a / b')
    await page.goto('/')
    const header = page.getByTestId('parts-section-header')
    await expect(header).toHaveText('a / b · 1')
    // `.list-group-header` renders uppercase — what the eye sees.
    await expect(header).toHaveText('A / B · 1', {useInnerText: true})

    await page.getByTestId('new-part').click()
    await page.getByTestId('part-name').fill('Rejected')
    await page.getByTestId('part-path').fill('a/?/b')
    await expect(page.getByTestId('part-path-error')).toBeVisible()
    await expect(page.getByTestId('part-path-error')).toContainText('"?"')
    await expect(page.getByTestId('part-create')).toBeDisabled()

    // Review S2: `A/B` typed on a new part snaps into the existing `a/b`.
    await page.getByTestId('part-path').fill('A/B')
    await expect(page.getByTestId('part-path-error')).toHaveCount(0)
    await expect(page.getByTestId('part-create')).toBeEnabled()
    await page.getByTestId('part-create').click()
    await page.waitForURL(/#\/parts\/[^/]+\/?$/, {timeout: 10_000})
    await expect(page.locator('.shell-subtitle')).toHaveText('a / b')
    await page.goto('/')
    await expect(page.getByTestId('parts-section')).toHaveCount(1)
    await expect(header).toHaveText('a / b · 2')
  })
})
