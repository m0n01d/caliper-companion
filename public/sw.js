// Caliper Companion service worker — ported from ternpike/public/sw.js with
// the SKIP_CACHE allowlist and the push-notification handlers removed: v0
// makes no network calls of its own (SPEC §5), so there is nothing to skip,
// and no push feature to receive for. Everything else — the atomic critical
// precache, two-generation cache retention, SKIP_WAITING/GET_VERSION
// messages, network-first fetch with a shell fallback — is unchanged.
//
// Cache name is stamped with the git SHA at build time so old caches are
// cleaned up on deploy. PRECACHE_URLS is injected at build time from
// dist/assets so the SW knows the hashed JS/CSS filenames it needs to seed
// on install — without this, the very first visit doesn't populate the
// cache (the SW activates *after* the page has already fetched its
// resources, so going offline before a second online visit leaves nothing
// to serve).
const CACHE = '__CACHE_VERSION__';
const PRECACHE_URLS = '__PRECACHE_URLS__';

const APP_SHELL = ['/', '/manifest.json', '/favicon.svg', '/icon-192.png', '/icon-512.png', '/apple-touch-icon.png'];

// The app shell minus '/' — incidental assets whose absence still leaves a
// usable build. '/' plus the hashed entry JS/CSS are handled separately below.
const INCIDENTAL = APP_SHELL.filter(u => u !== '/');

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE).then(async c => {
      // ATOMIC critical set. This install does not call `skipWaiting()`, so
      // activation can happen hours later and possibly OFFLINE. A holed
      // precache would strand the user on an unusable generation.
      // `addAll` is all-or-nothing: a partial precache fails install, the
      // worker never reaches `waiting`, and no toast is ever offered.
      const critical = ['/', ...(Array.isArray(PRECACHE_URLS) ? PRECACHE_URLS : [])];
      await c.addAll(critical);
      // Icons / manifest stay tolerant: missing ones don't break the app.
      await Promise.all(
        INCIDENTAL.map(u => c.add(u).catch(err => console.warn('[sw] precache failed', u, err)))
      );
    })
  );
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => {
        // Keep the current generation AND the most recent previous one. A
        // user who ignores the update leaves nothing to serve offline if
        // every non-current cache is deleted the moment a new generation
        // activates. `caches.keys()` resolves oldest-first, so the tail of
        // the non-current list is the previous generation.
        const others = keys.filter(k => k !== CACHE);
        const stale = others.slice(0, Math.max(0, others.length - 1));
        return Promise.all(stale.map(k => caches.delete(k)));
      })
      .then(() => self.clients.claim())
  );
});

self.addEventListener('message', event => {
  if (!event.data) return;
  if (event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
  if (event.data.type === 'GET_VERSION' && event.ports && event.ports[0]) {
    // Lets the page ask a waiting worker which generation it would serve.
    event.ports[0].postMessage({ version: CACHE });
  }
});

self.addEventListener('fetch', event => {
  const req = event.request;

  // Network-first for everything (index.html, entry JS, manifest, icons).
  // Online: always the latest build. Offline: cache fallback, with a final
  // fallback to the cached app shell ('/') for navigation requests so the
  // SPA loads even when the exact requested URL isn't cached.
  event.respondWith(
    fetch(req)
      .then(response => {
        const clone = response.clone();
        caches.open(CACHE).then(c => c.put(req, clone));
        return response;
      })
      .catch(async () => {
        const c = await caches.open(CACHE);
        const cached = await c.match(req);
        if (cached) return cached;
        if (req.mode === 'navigate') {
          const shell = await c.match('/');
          if (shell) return shell;
        }
        return Response.error();
      })
  );
});
