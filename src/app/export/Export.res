// Export — M5 entry point (SPEC §8 M5, M6 bullet 2). The Part page calls
// `run`; this module owns everything behind it — Render (the dimensioned
// PNG) and Bundle (zip + share/download) do the work, this file wires them
// together, gates on Reconcile, and stops the dogfood timer.

type error =
  | KindConflict(string) // a feature name has mixed kinds; export is blocked (SPEC M5)
  | NoFaces // nothing to export yet
  | Failed(string) // anything else, user-readable

type outcome =
  | Shared // navigator.share({files}) completed
  | Downloaded(string) // fallback anchor download; the file name

let run = async (store: Store.t, ~partId: string, ~appVersion: string): result<outcome, error> => {
  let exnMessage = (exn: exn): string =>
    switch exn {
    | JsExn(err) => JsExn.message(err)->Option.getOr("Export failed")
    | _ => "Export failed"
    }

  // The whole flow (SPEC §8 M5 / M6 bullet 2), as one attempt wrapped by the
  // catch-all below so a DOM/canvas exception this module didn't
  // anticipate still surfaces as `Error(Failed(_))` rather than a rejected
  // promise — the Part page only has to handle this module's own contract.
  let attempt = async (): result<outcome, error> =>
    switch await Store.getPart(store, partId) {
    | None => Error(Failed("Part not found"))
    | Some(part) =>
      let faces = await Store.facesOf(store, ~partId)
      if Array.length(faces) == 0 {
        Error(NoFaces)
      } else {
        let dimensions = await Store.dimensionsOf(store, ~partId)
        // SPEC M5: a kind conflict blocks export "before rendering
        // anything" — checked here, before the timer stops or a single
        // pixel is drawn.
        switch Reconcile.reconcile(dimensions) {
        | Error(Reconcile.KindConflict(name)) => Error(KindConflict(name))
        | Ok(_) =>
          // SPEC M6 bullet 2: the dogfood timer stops at the *first*
          // export; `Store.stopTimer` is idempotent, so re-exports are
          // safe to call this on every time.
          let _ = await Store.stopTimer(store, ~partId)
          let timer = await Store.getTimer(store, ~partId)
          let handsOnSeconds = timer->Option.flatMap(Store.handsOnSeconds)

          let renderOneFace = async (
            face: Types.face,
          ): result<(Types.face, float, Bundle.faceBundle), error> =>
            switch await Store.getFaceImage(store, face.id) {
            | None =>
              Error(Failed("Missing image for face " ++ face.label))
            | Some(image) =>
              let originalBuf = await PouchDb.blobArrayBuffer(image)
              let original = Uint8Array.fromBuffer(originalBuf)
              let faceDimensions = dimensions->Array.filter(d => d.faceId == face.id)
              // `renderScale` stays a real, computed value here (not
              // hardcoded) even though SPEC §8a A4's 2048px capture-time
              // cap means it's always `1.0` in practice now — `image` is
              // already at or under Render's own 4096 cap by the time it
              // gets here, so that branch is unreachable, not removed (see
              // Render.res's `canvasCapLongEdge` comment).
              let (pngBlob, renderWidth, renderHeight, renderScale) = await Render.renderFace(
                ~faceImage=image,
                ~dimensions=faceDimensions,
                ~units=part.units,
              )
              let pngBuf = await PouchDb.blobArrayBuffer(pngBlob)
              let dimensioned = Uint8Array.fromBuffer(pngBuf)
              // The face actually rendered — pixelWidth/Height reflect the
              // fresh oriented decode Render just did, so `features.json`
              // can never disagree with the PNG it shipped alongside.
              let renderedFace: Types.face = {
                ...face,
                pixelWidth: renderWidth,
                pixelHeight: renderHeight,
              }
              Ok((renderedFace, renderScale, ({label: face.label, original, dimensioned}: Bundle.faceBundle)))
            }

          // SPEC M5 bullet 5: faces are exported "in Store order" — `faces`
          // is already that order (Store.facesOf), and mapping preserves it.
          let rendered = await Promise.all(Array.map(faces, renderOneFace))
          let combined = Array.reduce(rendered, Ok([]), (acc, item) =>
            switch (acc, item) {
            | (Error(err), _) => Error(err)
            | (_, Error(err)) => Error(err)
            | (Ok(xs), Ok(x)) => Ok(Array.concat(xs, [x]))
            }
          )

          switch combined {
          | Error(err) => Error(err)
          | Ok(items) =>
            let faceExports: array<FeaturesDocument.faceExport> = Array.map(items, (
              (face, renderScale, _),
            ) => ({face, renderScale}: FeaturesDocument.faceExport))
            let bundleFaces = Array.map(items, ((_, _, fb)) => fb)
            switch FeaturesDocument.make(
              ~part,
              ~faces=faceExports,
              ~dimensions,
              ~exportedAt=Clock.nowIso(),
              ~appVersion,
              ~handsOnSeconds,
            ) {
            // Defensive only: `dimensions` hasn't changed since the
            // Reconcile check above already proved this Ok.
            | Error(Reconcile.KindConflict(name)) => Error(KindConflict(name))
            | Ok(json) =>
              // SPEC §8a A11: parameters.csv rides in the same bundle,
              // built from the same `dimensions` the Reconcile check above
              // already cleared — so this can't KindConflict either; kept
              // as a real switch (not Result.getExn) only to stay defensive
              // in lockstep with FeaturesDocument.make just above.
              let renderedFaces = Array.map(items, ((face, _, _)) => face)
              switch ParametersCsv.make(~part, ~faces=renderedFaces, ~dimensions) {
              | Error(Reconcile.KindConflict(name)) => Error(KindConflict(name))
              | Ok(parametersCsv) =>
                let zipBytes = Bundle.buildZipBytes(
                  ~featuresJson=json,
                  ~parametersCsv,
                  ~faces=bundleFaces,
                )
                let fileName = Bundle.fileNameFor(~slug=part.slug)
                switch await Bundle.deliver(~zipBytes, ~fileName, ~shareTitle=part.name) {
                | Ok(Bundle.Shared) => Ok(Shared)
                | Ok(Bundle.Downloaded(downloadedName)) => Ok(Downloaded(downloadedName))
                | Error(Bundle.ShareCancelled) => Error(Failed("Share cancelled"))
                | Error(Bundle.Failed(msg)) => Error(Failed(msg))
                }
              }
            }
          }
        }
      }
    }

  try {
    await attempt()
  } catch {
  | e => Error(Failed(exnMessage(e)))
  }
}
