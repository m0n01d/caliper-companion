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
