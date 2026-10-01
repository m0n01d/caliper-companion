// shell.spec.js — SPEC §8 M6 acceptance for the app shell: routing renders
// the right stub, the back button returns to `/`, and the shell still
// renders after an offline reload once the service worker controls the page.
import {test, expect} from '@playwright/test'

test.describe('app shell', () => {
  test('/ shows the parts-list empty state', async ({page}) => {
    await page.goto('/')
    await expect(page.locator('.shell-title')).toHaveText('Parts')
    await expect(page.getByText('No parts yet.', {exact: false})).toBeVisible()
    await expect(page.getByRole('button', {name: 'New part'})).toBeVisible()
  })

  test('Settings is reached from the Parts bar, Debug from Settings; Back walks the same way home', async ({
    page,
  }) => {
    // No URL bar in an installed app — the gear in the root bar is the only
    // way in, and the Diagnostics row the only way on to Debug.
    await page.goto('/')
    await page.getByRole('link', {name: 'Settings'}).click()
    await expect(page).toHaveURL(/#\/settings$/)
    await expect(page.locator('.shell-title')).toHaveText('Settings')
    await expect(page.getByText('Readings come from a connected caliper')).toBeVisible()
    await page.getByRole('button', {name: 'Back'}).click()
    await expect(page).toHaveURL(/#\/?$/)
    await expect(page.locator('.shell-title')).toHaveText('Parts')

    await page.goto('/#/settings')
    await page.getByTestId('debug-link').getByRole('link').click()
    await expect(page).toHaveURL(/#\/debug$/)
    await expect(page.locator('.shell-title')).toHaveText('Debug')
    await expect(page.getByRole('heading', {name: 'Timers'})).toBeVisible()
    // Viewport readout (LOGBOOK 2026-09-17 "iOS 26/27 standalone"): every
    // probe row renders with a real measurement.
    await expect(page.getByRole('heading', {name: 'Viewport'})).toBeVisible()
    await expect(page.getByTestId('viewport-row')).toHaveCount(13)
    await expect(page.getByTestId('viewport-row').filter({hasText: '100dvh'})).toContainText('844.0')
    await page.getByRole('button', {name: 'Back'}).click()
    await expect(page).toHaveURL(/#\/settings$/)
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

    // `install`'s critical `addAll([BASE, ...])` already finished before
    // `ready` resolved (see sw.js), so this should be immediate — but wait
    // for it explicitly rather than race the offline reload against it.
    // `./` resolves against the page, so this holds under any base path.
    await page.waitForFunction(async () => !!(await caches.match('./')))

    await context.setOffline(true)
    try {
      await page.reload()
      await expect(page.locator('.shell')).toBeVisible()
    } finally {
      await context.setOffline(false)
    }
  })
})
