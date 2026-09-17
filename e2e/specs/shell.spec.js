// shell.spec.js — SPEC §8 M6 acceptance for the app shell: routing renders
// the right stub, the back button returns to `/`, and the shell still
// renders after an offline reload once the service worker controls the page.
import {test, expect} from '@playwright/test'

test.describe('app shell', () => {
  test('/ shows the parts-list empty state', async ({page}) => {
    await page.goto('/')
    await expect(page.locator('.shell-title')).toHaveText('Parts')
    await expect(page.locator('.page-name')).toHaveText('PartsList')
    await expect(page.getByText('No parts yet.', {exact: false})).toBeVisible()
    await expect(page.getByRole('button', {name: 'New part'})).toBeVisible()
  })

  test('#/settings and #/debug render their stubs; back returns to /', async ({page}) => {
    await page.goto('/#/settings')
    await expect(page.locator('.shell-title')).toHaveText('Settings')
    await expect(page.locator('.page-name')).toHaveText('Settings')
    await expect(page.getByText('Readings come from a wedge dongle')).toBeVisible()
    await page.getByRole('button', {name: 'Back'}).click()
    await expect(page).toHaveURL(/#\/?$/)
    await expect(page.locator('.shell-title')).toHaveText('Parts')

    await page.goto('/#/debug')
    await expect(page.locator('.shell-title')).toHaveText('Debug')
    await expect(page.getByRole('heading', {name: 'Timers'})).toBeVisible()
    await page.getByRole('button', {name: 'Back'}).click()
    await expect(page).toHaveURL(/#\/?$/)
    await expect(page.locator('.shell-title')).toHaveText('Parts')
  })

  // SPEC M6: "app launches offline from the home screen." Chromium only
  // (see e2e/README.md for WebKit's launch status in this environment) —
  // the SW/offline mechanics are engine-agnostic, so one engine proves it.
  test('launches offline once the service worker controls the page', async ({page, context, browserName}) => {
    test.skip(browserName !== 'chromium', 'verified on chromium only here, see e2e/README.md')

    await page.goto('/')
    await page.evaluate(() => navigator.serviceWorker.ready)

    const controlled = await page.evaluate(() => !!navigator.serviceWorker.controller)
    if (!controlled) {
      // First visit: the worker that just installed doesn't control this
      // page yet (see sw.js's install-event comment). One reload is enough.
      await page.reload()
      await page.waitForFunction(() => !!navigator.serviceWorker.controller)
    }

    // `install`'s critical `addAll(['/', ...])` already finished before
    // `ready` resolved (see sw.js), so this should be immediate — but wait
    // for it explicitly rather than race the offline reload against it.
    await page.waitForFunction(async () => !!(await caches.match('/')))

    await context.setOffline(true)
    try {
      await page.reload()
      await expect(page.locator('.shell')).toBeVisible()
      await expect(page.locator('.page-name')).toHaveText('PartsList')
    } finally {
      await context.setOffline(false)
    }
  })
})
