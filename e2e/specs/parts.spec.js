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
// or path, and the shared create/rename form's Folder row moves a part.
// Named parts per docs/design/a10-folders-review.md S7 so "search `bezel`
// filters to one" is a real assertion.
//
// A12a: the Folder field is a picker. `pickFolder` walks a path's segments
// — selecting the `folder-option` when it exists, else making it with New
// Folder (a new folder nests under whatever is selected, so the walk keeps
// the parent selected) — then taps Done.
const optionFor = (page, path) => page.locator(`[data-testid="folder-option"][data-path="${path}"]`)

async function pickFolder(page, folder) {
  await page.getByTestId('part-folder-row').click()
  await expect(page.getByTestId('folder-picker-list')).toBeVisible()
  const segments = folder === '' ? [] : folder.split('/')
  let path = ''
  for (const segment of segments) {
    path = path === '' ? segment : `${path}/${segment}`
    const option = optionFor(page, path)
    if ((await option.count()) === 0) {
      await page.getByTestId('folder-new').click()
      await page.getByTestId('folder-new-name').fill(segment)
      await page.getByTestId('folder-new-create').click()
    } else {
      await option.click()
    }
    await expect(option).toHaveAttribute('aria-selected', 'true')
  }
  if (segments.length === 0) {
    await optionFor(page, '').click()
  }
  await page.getByTestId('folder-picker-done').click()
  await expect(page.getByTestId('part-folder-row')).toContainText(
    folder === '' ? 'None' : segments.join(' / '),
  )
}

async function createPartIn(page, name, folder) {
  await page.goto('/')
  await page.getByTestId('new-part').click()
  await page.getByTestId('part-name').fill(name)
  if (folder !== undefined) {
    await pickFolder(page, folder)
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

    // The rename strip's Folder row opens the picker (A12a); choosing the
    // existing folder moves the part: the root section disappears and the
    // moved part re-sorts to the top of its new section (S6).
    await page.getByTestId('parts-edit').click()
    await sections.nth(0).getByTestId('part-rename').click()
    await expect(page.getByTestId('part-rename-input')).toHaveValue('Hinge pin')
    await expect(page.getByTestId('part-folder-row')).toContainText('None')
    await page.getByTestId('part-folder-row').click()
    // The picker takes over the page: bar title, no list, no search.
    await expect(page.locator('.shell-title')).toHaveText('Choose Folder')
    await expect(page.getByTestId('part-row')).toHaveCount(0)
    await expect(page.getByTestId('parts-search')).toHaveCount(0)
    await optionFor(page, 'Miata/Interior').click()
    await page.getByTestId('folder-picker-done').click()
    await expect(page.getByTestId('part-folder-row')).toContainText('Miata / Interior')
    await expect(page.getByTestId('part-folder-row')).toBeFocused()
    await page.getByTestId('part-rename-save').click()
    await expect(page.getByTestId('parts-section')).toHaveCount(1)
    await expect(page.getByTestId('parts-section-header')).toHaveText('Miata / Interior · 3')
    await expect(page.getByTestId('part-row').first()).toContainText('Hinge pin')

    await page.reload()
    await expect(page.getByTestId('parts-section')).toHaveCount(1)
    await expect(page.getByTestId('parts-section-header')).toHaveText('Miata / Interior · 3')
    await expect(page.getByTestId('part-row').first()).toContainText('Hinge pin')
  })
})

// SPEC §8a A12a — the folder picker: a take-over screen with a flat tree of
// every folder, a New Folder field that nests under the selection and snaps
// onto an existing spelling, and Cancel/Done that return to the form.
test.describe('parts — folders — picker (SPEC §8a A12a)', () => {
  test('New Folder nests under the selection; Done fills the row; create and rename go through the picker', async ({
    page,
  }) => {
    await page.goto('/')
    await page.getByTestId('new-part').click()
    await page.getByTestId('part-name').fill('Window switch bezel')
    await expect(page.getByTestId('part-folder-row')).toContainText('None')
    await page.getByTestId('part-folder-row').click()

    // Bar (review B3): centred "Choose Folder" between Cancel and Done —
    // no Large Title, no gear, no Edit/"+".
    await expect(page.locator('.shell-title')).toHaveText('Choose Folder')
    await expect(page.locator('.shell-large-title')).toHaveCount(0)
    await expect(page.getByTestId('folder-picker-cancel')).toBeVisible()
    await expect(page.getByTestId('folder-picker-done')).toBeVisible()
    await expect(page.getByTestId('settings-link')).toHaveCount(0)
    await expect(page.getByTestId('parts-edit')).toHaveCount(0)
    await expect(page.getByTestId('folder-picker-list')).toHaveAttribute('role', 'listbox')
    const options = page.getByTestId('folder-option')
    await expect(options).toHaveCount(1)
    await expect(options.first()).toHaveAttribute('data-path', '')
    await expect(options.first()).toHaveAttribute('aria-label', 'None, top level')
    await expect(options.first()).toHaveAttribute('aria-selected', 'true')
    await expect(options.first()).toBeFocused()

    // New Folder: the field opens focused, Create is disabled while empty,
    // the created folder becomes the selection and takes focus.
    await page.getByTestId('folder-new').click()
    await expect(page.getByTestId('folder-new-name')).toBeFocused()
    await expect(page.getByTestId('folder-new-name')).toHaveAttribute('placeholder', 'Folder name')
    await expect(page.getByTestId('folder-new-create')).toBeDisabled()
    await page.getByTestId('folder-new-name').fill('Miata')
    await page.getByTestId('folder-new-create').click()
    await expect(options).toHaveCount(2)
    await expect(optionFor(page, 'Miata')).toHaveAttribute('aria-selected', 'true')
    await expect(optionFor(page, 'Miata')).toBeFocused()
    await expect(page.getByTestId('folder-new-name')).toHaveCount(0)

    // With Miata selected, the next one nests under it (Enter creates too).
    await page.getByTestId('folder-new').click()
    await page.getByTestId('folder-new-name').fill('Interior')
    await page.getByTestId('folder-new-name').press('Enter')
    await expect(options).toHaveCount(3)
    await expect(options.nth(0)).toHaveAttribute('data-path', '')
    await expect(options.nth(1)).toHaveAttribute('data-path', 'Miata')
    await expect(options.nth(2)).toHaveAttribute('data-path', 'Miata/Interior')
    await expect(options.nth(2)).toHaveAttribute('aria-label', 'Miata / Interior')
    await expect(options.nth(2)).toHaveAttribute('aria-selected', 'true')
    await expect(options.nth(1)).toHaveAttribute('aria-selected', 'false')
    // Visible text is the leaf; the child sits one 20 px step in from its parent.
    await expect(options.nth(1)).toHaveText('Miata')
    await expect(options.nth(2)).toHaveText('Interior')
    const padding = loc => loc.evaluate(el => parseFloat(getComputedStyle(el).paddingLeft))
    expect((await padding(options.nth(2))) - (await padding(options.nth(1)))).toBe(20)
    expect((await padding(options.nth(1))) - (await padding(options.nth(0)))).toBe(20)

    // Done returns to the form with the row filled and focused; Name intact.
    await page.getByTestId('folder-picker-done').click()
    await expect(page.locator('.shell-title')).toHaveText('Parts')
    await expect(page.getByTestId('part-folder-row')).toContainText('Miata / Interior')
    await expect(page.getByTestId('part-folder-row')).toBeFocused()
    await expect(page.getByTestId('part-name')).toHaveValue('Window switch bezel')
    await page.getByTestId('part-create').click()
    await page.waitForURL(/#\/parts\/[^/]+\/?$/, {timeout: 10_000})
    await expect(page.locator('.shell-subtitle')).toHaveText('Miata / Interior')
    await page.goto('/')
    await expect(page.getByTestId('parts-section-header')).toHaveText('Miata / Interior · 1')

    // A root part, moved through the rename strip's own Folder row.
    await createPartIn(page, 'Hinge pin')
    await page.goto('/')
    await expect(page.getByTestId('parts-section')).toHaveCount(2)
    await page.getByTestId('parts-edit').click()
    await page.getByTestId('parts-section').nth(0).getByTestId('part-rename').click()
    await page.getByTestId('part-folder-row').click()
    await optionFor(page, 'Miata/Interior').click()
    await page.getByTestId('folder-picker-done').click()
    await page.getByTestId('part-rename-save').click()
    await expect(page.getByTestId('parts-section')).toHaveCount(1)
    await expect(page.getByTestId('parts-section-header')).toHaveText('Miata / Interior · 2')
  })

  test('new-folder field: a/b and ? are rejected inline, a case variant snaps to the existing spelling; Cancel keeps the Name; a created folder persists', async ({
    page,
  }) => {
    await createPartIn(page, 'Window switch bezel', 'Miata/Interior')
    await page.goto('/')
    await page.getByTestId('new-part').click()
    await page.getByTestId('part-name').fill('Kept name')
    await page.getByTestId('part-folder-row').click()
    // The tree lists the parts' folders and their ancestors: None, Miata, Interior.
    const options = page.getByTestId('folder-option')
    await expect(options).toHaveCount(3)
    await optionFor(page, 'Miata').click()
    await page.getByTestId('folder-new').click()
    const name = page.getByTestId('folder-new-name')
    await name.fill('a/b')
    await expect(page.getByTestId('folder-new-error')).toBeVisible()
    await expect(page.getByTestId('folder-new-error')).toContainText('Folder name "a/b" can use')
    await expect(page.getByTestId('folder-new-create')).toBeDisabled()
    await name.fill('?')
    await expect(page.getByTestId('folder-new-error')).toContainText('"?"')
    await expect(page.getByTestId('folder-new-create')).toBeDisabled()
    // A case-only variant of an existing sibling selects it — no twin.
    await name.fill('interior')
    await expect(page.getByTestId('folder-new-error')).toHaveCount(0)
    await expect(page.getByTestId('folder-new-create')).toBeEnabled()
    await page.getByTestId('folder-new-create').click()
    await expect(options).toHaveCount(3)
    await expect(optionFor(page, 'Miata/Interior')).toHaveAttribute('aria-selected', 'true')
    await expect(optionFor(page, 'Miata/interior')).toHaveCount(0)

    // A folder made in the picker is real even if the picker is then
    // Cancelled; Cancel keeps the form's Name and focuses the Folder row.
    await optionFor(page, '').click()
    await page.getByTestId('folder-new').click()
    await name.fill('Archive')
    await page.getByTestId('folder-new-create').click()
    await expect(optionFor(page, 'Archive')).toHaveAttribute('aria-selected', 'true')
    await page.getByTestId('folder-picker-cancel').click()
    await expect(page.getByTestId('part-name')).toHaveValue('Kept name')
    await expect(page.getByTestId('part-folder-row')).toContainText('None')
    await expect(page.getByTestId('part-folder-row')).toBeFocused()
    await page.getByTestId('part-folder-row').click()
    await expect(optionFor(page, 'Archive')).toHaveCount(1)
    await expect(optionFor(page, '')).toHaveAttribute('aria-selected', 'true')
    await page.getByTestId('folder-picker-cancel').click()
    // …and it survives a reload (it is a `folder:` doc, not page state).
    await page.reload()
    await page.getByTestId('new-part').click()
    await page.getByTestId('part-folder-row').click()
    await expect(optionFor(page, 'Archive')).toHaveCount(1)
  })

  test('at six deep, New Folder is disabled with a footnote', async ({page}) => {
    await page.goto('/')
    await page.getByTestId('new-part').click()
    await page.getByTestId('part-name').fill('Deep part')
    await pickFolder(page, 'a/b/c/d/e/f')
    await page.getByTestId('part-folder-row').click()
    await expect(optionFor(page, 'a/b/c/d/e/f')).toHaveAttribute('aria-selected', 'true')
    await expect(page.getByTestId('folder-new')).toBeDisabled()
    await expect(page.getByTestId('folder-new-depth')).toHaveText('Folders go six deep.')
    await optionFor(page, 'a/b/c/d/e').click()
    await expect(page.getByTestId('folder-new')).toBeEnabled()
    await expect(page.getByTestId('folder-new-depth')).toHaveCount(0)
  })
})
