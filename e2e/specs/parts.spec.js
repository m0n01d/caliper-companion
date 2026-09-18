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

    // A12b: delete lives in the Edit-mode toolbar — check the row, then
    // Delete opens the confirm strip in the same slot. With no parts left,
    // Edit leaves the bar and focus goes to the empty state's own capsule.
    await page.getByTestId('parts-edit').click()
    await expect(page.getByTestId('parts-delete')).toHaveText('Delete')
    await expect(page.getByTestId('parts-delete')).toBeDisabled()
    await page.getByTestId('part-select').check()
    await expect(page.getByTestId('parts-delete')).toHaveText('Delete 1')
    await page.getByTestId('parts-delete').click()
    await expect(page.getByTestId('edit-toolbar')).toContainText(
      'Delete 1 part? This removes its faces and dimensions.',
    )
    await page.getByTestId('parts-delete-confirm').click()

    await expect(page.getByTestId('parts-empty')).toBeVisible()
    await expect(page.getByTestId('part-row')).toHaveCount(0)
    await expect(page.getByTestId('parts-live')).toHaveText('Deleted 1 part')
    await expect(page.getByTestId('parts-edit')).toHaveCount(0)
    await expect(page.getByTestId('edit-toolbar')).toHaveCount(0)
    await expect(page.getByTestId('new-part')).toBeFocused()
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

// SPEC §8a A12b — folder management: Edit mode selects rows for the bottom
// toolbar's Move (the picker, `ForMove`) and Delete (one confirm strip);
// section headers rename inline (the subtree follows) and delete when
// empty; an explicit leaf folder with no parts is a "· 0" section.
const folderButton = (page, id, path) => page.locator(`[data-testid="${id}"][data-path="${path}"]`)

// A folder made in the picker is a real doc even if the picker is then
// Cancelled (A12a) — the way to get an empty folder.
async function createEmptyFolder(page, name) {
  await page.goto('/')
  await page.getByTestId('new-part').click()
  await page.getByTestId('part-folder-row').click()
  await optionFor(page, '').click()
  await page.getByTestId('folder-new').click()
  await page.getByTestId('folder-new-name').fill(name)
  await page.getByTestId('folder-new-create').click()
  await expect(optionFor(page, name)).toHaveAttribute('aria-selected', 'true')
  await page.getByTestId('folder-picker-cancel').click()
  await page.getByRole('button', {name: 'Cancel'}).click()
  await expect(page.getByTestId('part-name')).toHaveCount(0)
}

test.describe('parts — folders — management (SPEC §8a A12b)', () => {
  test('an empty folder is a · 0 section; Edit selects rows; Move 2 goes through the picker; Delete 1 through the toolbar', async ({
    page,
  }) => {
    await createPartIn(page, 'Window switch bezel', 'Miata/Interior')
    await createPartIn(page, 'Hinge pin')
    await createPartIn(page, 'Door card clip')
    await createEmptyFolder(page, 'Archive')

    // Root (headerless), Archive · 0 with its one Footnote row, Miata / Interior · 1.
    const sections = page.getByTestId('parts-section')
    await expect(sections).toHaveCount(3)
    const headers = page.getByTestId('parts-section-header')
    await expect(headers).toHaveCount(2)
    await expect(headers.nth(0)).toHaveText('Archive · 0')
    await expect(headers.nth(1)).toHaveText('Miata / Interior · 1')
    await expect(page.getByTestId('parts-section-empty')).toHaveText('Empty folder')
    await expect(sections.nth(1).getByTestId('parts-section-empty')).toHaveCount(1)
    await expect(page.getByTestId('edit-toolbar')).toHaveCount(0)
    // Search hides an empty folder unless its path matches the query.
    await page.getByTestId('parts-search').fill('arch')
    await expect(sections).toHaveCount(1)
    await expect(headers).toHaveText(['Archive · 0'])
    await expect(page.getByTestId('parts-search-empty')).toHaveCount(0)
    await page.getByTestId('parts-search').fill('bezel')
    await expect(sections).toHaveCount(1)
    await expect(headers).toHaveText(['Miata / Interior · 1'])
    await page.getByTestId('parts-search-clear').click()
    await expect(sections).toHaveCount(3)

    // Edit: rows are checkbox rows — no link anywhere in a section — and the
    // toolbar's actions are disabled until something is checked.
    await page.getByTestId('parts-edit').click()
    await expect(page.getByTestId('parts-section').getByRole('link')).toHaveCount(0)
    await expect(page.getByTestId('part-row')).toHaveCount(3)
    await expect(page.getByTestId('part-delete')).toHaveCount(0)
    await expect(page.getByTestId('parts-move')).toHaveText('Move')
    await expect(page.getByTestId('parts-move')).toBeDisabled()
    await expect(page.getByTestId('parts-delete')).toBeDisabled()
    const checks = page.getByTestId('part-select')
    await expect(checks).toHaveCount(3)
    await expect(checks.nth(0)).toHaveAttribute('aria-label', 'Select Door card clip')
    // The body is the checkbox's label: tapping the title toggles.
    await sections.nth(0).getByText('Door card clip').click()
    await expect(checks.nth(0)).toBeChecked()
    await checks.nth(1).check()
    await expect(page.getByTestId('parts-move')).toHaveText('Move 2')
    await expect(page.getByTestId('parts-delete')).toHaveText('Delete 2')
    // The pencil is outside the label — it opens the rename strip, no toggle.
    await sections.nth(0).getByTestId('part-rename').first().click()
    await expect(page.getByTestId('part-rename-input')).toBeFocused()
    await page.getByTestId('part-rename-cancel').click()
    await expect(page.getByTestId('parts-move')).toHaveText('Move 2')

    // Move: the picker takes over titled by the count, root preselected;
    // Cancel keeps the selection and focuses Move.
    await page.getByTestId('parts-move').click()
    await expect(page.locator('.shell-title')).toHaveText('Move 2 Parts')
    await expect(page.getByTestId('edit-toolbar')).toHaveCount(0)
    await expect(page.getByTestId('part-row')).toHaveCount(0)
    await expect(optionFor(page, '')).toHaveAttribute('aria-selected', 'true')
    await expect(optionFor(page, '')).toBeFocused()
    await page.getByTestId('folder-picker-cancel').click()
    await expect(page.getByTestId('parts-move')).toHaveText('Move 2')
    await expect(page.getByTestId('parts-move')).toBeFocused()
    await page.getByTestId('parts-move').click()
    await optionFor(page, 'Archive').click()
    await page.getByTestId('folder-picker-done').click()
    await expect(headers).toHaveText(['Archive · 2', 'Miata / Interior · 1'])
    await expect(sections).toHaveCount(2)
    await expect(page.getByTestId('parts-section-empty')).toHaveCount(0)
    await expect(page.getByTestId('parts-live')).toHaveText('Moved 2 parts to Archive')
    await expect(page.getByTestId('parts-move')).toBeFocused()
    await expect(page.getByTestId('parts-move')).toHaveText('Move')
    await expect(page.getByTestId('parts-edit')).toHaveText('Done')
    // Moving a part into the folder it is already in announces nothing new.
    await checks.nth(0).check()
    await page.getByTestId('parts-move').click()
    await optionFor(page, 'Archive').click()
    await page.getByTestId('folder-picker-done').click()
    await expect(page.getByTestId('parts-live')).toHaveText('Moved 2 parts to Archive')
    await expect(page.getByTestId('parts-move')).toHaveText('Move')

    // Delete one: the confirm strip sits in the toolbar, focus lands on its
    // Cancel; confirming removes the row and focuses Edit/Done.
    await checks.nth(2).check()
    await expect(page.getByTestId('parts-delete')).toHaveText('Delete 1')
    await page.getByTestId('parts-delete').click()
    await expect(page.getByTestId('parts-move')).toHaveCount(0)
    await expect(page.getByTestId('edit-toolbar')).toContainText(
      'Delete 1 part? This removes its faces and dimensions.',
    )
    await expect(page.getByTestId('parts-delete-cancel')).toBeFocused()
    await page.getByTestId('parts-delete-cancel').click()
    await expect(page.getByTestId('parts-delete')).toHaveText('Delete 1')
    await expect(page.getByTestId('parts-delete')).toBeFocused()
    await page.getByTestId('parts-delete').click()
    await page.getByTestId('parts-delete-confirm').click()
    await expect(page.getByTestId('part-row')).toHaveCount(2)
    // The folder the deleted part lived in stays as an empty · 0 section.
    await expect(sections).toHaveCount(2)
    await expect(headers).toHaveText(['Archive · 2', 'Miata / Interior · 0'])
    await expect(page.getByTestId('parts-section-empty')).toHaveCount(1)
    await expect(page.getByTestId('parts-live')).toHaveText('Deleted 1 part')
    await expect(page.getByTestId('parts-edit')).toBeFocused()
    await expect(page.getByTestId('parts-edit')).toHaveText('Done')
    // Done clears the leftover state; everything above persisted.
    await page.getByTestId('parts-edit').click()
    await expect(page.getByTestId('edit-toolbar')).toHaveCount(0)
    await page.reload()
    await expect(headers).toHaveText(['Archive · 2', 'Miata / Interior · 0'])
    await expect(page.getByTestId('part-row')).toHaveCount(2)
  })

  test('folder rename: an intermediate folder is a header-only row while editing; the subtree follows; case-only saves; a sibling twin and a slash are refused inline', async ({
    page,
  }) => {
    await createPartIn(page, 'Window switch bezel', 'Miata/Interior')
    await createPartIn(page, 'Bracket', 'Archive')
    await page.goto('/')
    // Miata (subfolders, no direct parts) renders nothing outside Edit mode.
    await expect(page.getByTestId('parts-section')).toHaveCount(2)
    await expect(page.getByTestId('parts-folder-header')).toHaveCount(0)
    await expect(page.getByTestId('folder-rename')).toHaveCount(0)
    await page.getByTestId('parts-edit').click()
    await expect(page.getByTestId('parts-section')).toHaveCount(2)
    await expect(page.getByTestId('parts-folder-header')).toHaveText('Miata')
    await expect(page.getByTestId('folder-rename')).toHaveCount(3)
    await expect(page.getByTestId('folder-delete')).toHaveCount(0)
    // The heading's accessible name is the heading alone — the buttons are
    // siblings, not children.
    await expect(page.getByRole('heading', {name: 'Archive · 1'})).toHaveCount(1)

    // Rename Miata → MX-5: prefilled, focused, Save disabled while unchanged.
    await folderButton(page, 'folder-rename', 'Miata').click()
    const input = page.getByTestId('folder-rename-input')
    await expect(input).toBeFocused()
    await expect(input).toHaveValue('Miata')
    await expect(input).toHaveAttribute('enterkeyhint', 'done')
    await expect(page.getByTestId('folder-rename-save')).toBeDisabled()
    await expect(page.getByTestId('parts-folder-header')).toHaveCount(0)
    await input.fill('a/b')
    await expect(page.getByTestId('folder-rename-error')).toContainText('Folder name "a/b" can use')
    await expect(page.getByTestId('folder-rename-save')).toBeDisabled()
    await input.fill('MX-5')
    await expect(page.getByTestId('folder-rename-error')).toHaveCount(0)
    await page.getByTestId('folder-rename-save').click()
    await expect(page.getByTestId('parts-folder-header')).toHaveText('MX-5')
    await expect(page.getByTestId('parts-section-header')).toHaveText(['Archive · 1', 'MX-5 / Interior · 1'])
    await expect(folderButton(page, 'folder-rename', 'MX-5')).toBeFocused()
    await expect(page.getByTestId('folder-rename-form')).toHaveCount(0)

    // One inline editor at a time: a folder rename closes a row's strip and
    // vice versa.
    await page.getByTestId('part-rename').first().click()
    await expect(page.getByTestId('part-rename-input')).toHaveCount(1)
    await folderButton(page, 'folder-rename', 'MX-5/Interior').click()
    await expect(page.getByTestId('part-rename-input')).toHaveCount(0)
    await expect(page.getByTestId('folder-rename-form')).toHaveCount(1)
    await page.getByTestId('part-rename').first().click()
    await expect(page.getByTestId('folder-rename-form')).toHaveCount(0)
    await page.getByTestId('part-rename-cancel').click()

    // Case-only rename saves (Enter submits); Cancel focuses the pencil.
    await folderButton(page, 'folder-rename', 'MX-5/Interior').click()
    await input.fill('interior')
    await input.press('Enter')
    await expect(page.getByTestId('parts-section-header')).toHaveText(['Archive · 1', 'MX-5 / interior · 1'])
    await expect(folderButton(page, 'folder-rename', 'MX-5/interior')).toBeFocused()
    await folderButton(page, 'folder-rename', 'MX-5').click()
    await input.fill('archive')
    await page.getByTestId('folder-rename-save').click()
    await expect(page.getByTestId('folder-rename-error')).toHaveText(
      'A folder named "archive" already exists here.',
    )
    await expect(page.getByTestId('parts-folder-header')).toHaveCount(0)
    await page.getByTestId('folder-rename-cancel').click()
    await expect(page.getByTestId('parts-folder-header')).toHaveText('MX-5')
    await expect(folderButton(page, 'folder-rename', 'MX-5')).toBeFocused()

    // The part followed its folder: its page subtitle, and it all persisted.
    await page.getByTestId('parts-edit').click()
    await page.getByTestId('part-row').filter({hasText: 'Window switch bezel'}).getByRole('link').click()
    await expect(page.locator('.shell-subtitle')).toHaveText('MX-5 / interior')
    await page.goto('/')
    await page.reload()
    await expect(page.getByTestId('parts-section-header')).toHaveText(['Archive · 1', 'MX-5 / interior · 1'])
  })

  test('folder delete: only on an empty leaf, no confirm; deleting the last part exits Edit mode and leaves the folder as an empty section', async ({
    page,
  }) => {
    await createPartIn(page, 'Bracket', 'Miata/Interior')
    await createEmptyFolder(page, 'Archive')
    await expect(page.getByTestId('parts-section-header')).toHaveText(['Archive · 0', 'Miata / Interior · 1'])
    await page.getByTestId('parts-edit').click()
    await expect(page.getByTestId('folder-delete')).toHaveCount(1)
    await expect(folderButton(page, 'folder-delete', 'Archive')).toHaveAttribute('aria-label', 'Delete folder')
    await expect(folderButton(page, 'folder-delete', 'Miata/Interior')).toHaveCount(0)
    await expect(folderButton(page, 'folder-delete', 'Miata')).toHaveCount(0)
    await folderButton(page, 'folder-delete', 'Archive').click()
    await expect(page.getByTestId('parts-section-header')).toHaveText(['Miata / Interior · 1'])
    await expect(page.getByTestId('parts-live')).toHaveText('Deleted folder Archive')
    await expect(page.getByTestId('parts-edit')).toBeFocused()

    // Deleting the last part: Edit leaves the bar, focus goes to the empty
    // state's capsule, and the folder it lived in stays visible as a · 0
    // section under the empty state (it is a real doc, never "vanished").
    await page.getByTestId('part-select').check()
    await page.getByTestId('parts-delete').click()
    await page.getByTestId('parts-delete-confirm').click()
    await expect(page.getByTestId('parts-empty')).toBeVisible()
    await expect(page.getByTestId('parts-edit')).toHaveCount(0)
    await expect(page.getByTestId('new-part')).toBeFocused()
    await expect(page.getByTestId('parts-section-header')).toHaveText(['Miata / Interior · 0'])
    await expect(page.getByTestId('parts-section-empty')).toHaveCount(1)

    // Gone for good: the picker no longer lists Archive.
    await page.reload()
    await page.getByTestId('new-part').click()
    await page.getByTestId('part-folder-row').click()
    await expect(optionFor(page, 'Archive')).toHaveCount(0)
    await expect(optionFor(page, 'Miata/Interior')).toHaveCount(1)
  })
})
