# Demo

Recorded by `scripts/demo-tour.mjs` against a running dev server (see CLAUDE.md
"Testing on the phone"); the golden path at the SPEC's 390 × 844, with a cursor
overlay, subtitles and human pacing. Motion is deliberately NOT reduced — the A16
page pushes, the A6 fit tween and the polish-pass press/release are the point.

```sh
ASDF_NODEJS_VERSION=22.16.0 node scripts/demo-tour.mjs --rehearse   # verify every step
ASDF_NODEJS_VERSION=22.16.0 node scripts/demo-tour.mjs               # record to docs/demo/
```

The script writes `snapkin-demo.webm` (Playwright's native format); the committed
`public/beta/snapkin-demo.mp4` is that file through ffmpeg (H.264, CRF 24, faststart)
because WebM does not play everywhere a demo gets pasted. It lives next to the landing
page (`public/beta/`, the demo section), so a new recording goes there:

```sh
ffmpeg -i docs/demo/snapkin-demo.webm -c:v libx264 -crf 24 -movflags +faststart public/beta/snapkin-demo.mp4
```
