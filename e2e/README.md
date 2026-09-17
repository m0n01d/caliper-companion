# e2e

Playwright config: `e2e/playwright.config.js`. Two projects, both at the 390×844 phone viewport:

- **`chromium`** — runs clean in this environment.
- **`webkit`** — Safari's real engine, what iOS actually ships. **Cannot launch in this sandbox**
  (see below); kept defined per the app-shell agent's brief — don't delete it, don't try to
  apt-install the missing libraries here. Run it on a machine that has them (a Mac, or a Linux box
  with the GTK WebKit runtime deps installed).

`npm run e2e` builds first (`rescript build && vite build`) so tests run against the built `dist/`
via `vite preview` — the service-worker offline test needs the real stamped `sw.js`, which only
exists after a build.

## Running

```sh
npm run e2e                                                    # both projects
npx playwright test --config=e2e/playwright.config.js --project=chromium
npx playwright test --config=e2e/playwright.config.js --project=webkit
```

If a `vite preview` is already running on port 3000, the config's `reuseExistingServer: true`
attaches to it instead of starting a second one — useful when iterating on a single spec.

## WebKit launch status here (2026-09-17)

Fails with `browserType.launch` reporting missing shared libraries (GTK4 WebKit backend):

```
Host system is missing dependencies to run browsers.
Missing libraries:
    libgtk-4.so.1
    libgraphene-1.0.so.0
    libevent-2.1.so.7
    libopus.so.0
    libgstgl-1.0.so.0
    libgstcodecparsers-1.0.so.0
    libflite.so.1
    libflite_usenglish.so.1
    libflite_cmu_grapheme_lang.so.1
    libflite_cmu_grapheme_lex.so.1
    libflite_cmu_indic_lang.so.1
    libflite_cmu_indic_lex.so.1
    libflite_cmulex.so.1
    libflite_cmu_time_awb.so.1
    libflite_cmu_us_awb.so.1
    libflite_cmu_us_kal16.so.1
    libflite_cmu_us_kal.so.1
    libflite_cmu_us_rms.so.1
    libflite_cmu_us_slt.so.1
    libwebpdemux.so.2
    libwebpmux.so.3
    libwayland-server.so.0
    libmanette-0.2.so.0
    libenchant-2.so.2
    libsecret-1.so.0
    libwoff2dec.so.1.0.2
    libGLESv2.so.2
    libx264.so
```

The `webkit-2287` build at `/opt/pw-browsers/webkit-2287` is present (browsers are installed —
`PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers` is already set), it's the GTK/WPE system libraries the
binary links against that are missing from this sandbox's OS image. `chromium` has no equivalent
system-dependency problem because Playwright ships a statically-linked-enough Chromium.

`shell.spec.js`'s offline test explicitly skips on any browser but `chromium`
(`test.skip(browserName !== 'chromium', ...)`) for this reason — the service-worker mechanics it
verifies are engine-agnostic, so chromium alone is sufficient signal here, but the *real* target
platform for SPEC's iOS rules (§5, §10) is WebKit and that suite should be run for real on a Mac or
a Linux host with the GTK WebKit deps before trusting iOS-specific behavior.
