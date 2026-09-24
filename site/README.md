# snapkin.tools

The Snapkin landing page: static HTML, one CSS file, SVG art. No JavaScript and no build step.

- **Source:** `site/` in `m0n01d/caliper-companion`, next to the brand kit (`docs/brand/`).
- **Live:** `https://snapkin.tools`, served by GitHub Pages from its own repo (proposed:
  `m0n01d/snapkin-site`). A Pages site takes one custom domain, and `caliper-companion`'s Pages
  site is the app at `https://app.snapkin.tools`.

## Preview

```sh
python3 -m http.server 8080 -d site   # then open http://localhost:8080/
```

Serve it from its own root, as Pages does. `404.html` uses root paths (`/site.css`).

## Publish

From the root of `caliper-companion`:

```sh
git subtree push --prefix=site https://github.com/m0n01d/snapkin-site.git main
```

This pushes the contents of `site/` as the root of the site repo. That repo's Pages setting is
**Deploy from a branch → `main` → `/ (root)`**, so a push publishes. `CNAME` (`snapkin.tools`) and
`.nojekyll` (serve the files as they are) ship with the site.

## Domain

The DNS for `snapkin.tools` is at Squarespace. These are the records checked on 2026-09-24
(`m0n01d/caliper-companion` PR #3):

| Type | Host | Data |
|---|---|---|
| TXT | `_github-pages-challenge-m0n01d` | The value from github.com/settings/pages → Add a domain. It verifies the domain for the account. |
| A | `@` | `185.199.108.153`, `185.199.109.153`, `185.199.110.153`, `185.199.111.153` |
| AAAA | `@` | `2606:50c0:8000::153`, `2606:50c0:8001::153`, `2606:50c0:8002::153`, `2606:50c0:8003::153` |
| CNAME | `www` | `m0n01d.github.io` (GitHub then redirects www to the apex) |
| CNAME | `app` | `m0n01d.github.io` (the app, from `caliper-companion`) |

After the site repo shows the domain as verified, turn on **Enforce HTTPS** in its Pages settings.

## Things that name the domain

- `og:url`, `og:image` and `canonical` in `index.html` are absolute: `https://snapkin.tools/`.
- `404.html` links to `https://app.snapkin.tools/`.

## Sign-up

The form is disabled until a sign-up service is connected. See `docs/brand/README.md`, "Beta sign-up".
