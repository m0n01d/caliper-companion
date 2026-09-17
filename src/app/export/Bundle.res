// Bundle — zips `features.json` + the per-face images and delivers it via
// `Share.share` or the download fallback (SPEC §7 bundle layout, M5
// bullets 2–3). SPEC §13 leaves zip-vs-multi-file open; this ships zip
// only (`<slug>.ccpart.zip`) per the fixture/e2e contract in the M5 brief.
//
// Deliberately its own `outcome`/`error` rather than `Export`'s: `Export`
// is the caller here (`Export.run` drives `Bundle.deliver`), so reusing
// `Export`'s types would make this module depend on its caller — a cycle.
// `Export.res` maps these onto its own contract types instead.

type faceBundle = {
  // The face's label (SPEC §8a A7) — names both zip entries. Default faces
  // have `label == kind` ("top"), so their entries are the pre-A7 paths.
  label: string,
  // The original attachment's bytes, verbatim, whatever its real content
  // type — always zipped as `faces/<label>.jpg` per the frozen §7 contract
  // (SPEC M5 bullet 6 note: "name stays .jpg per the contract").
  original: Uint8Array.t,
  dimensioned: Uint8Array.t, // Render.renderFace's PNG output
}

let zipEntryPath = (label: string, ~suffix: string): string => "faces/" ++ label ++ suffix

// SPEC §8a A11: `parameters.csv` sits next to `features.json` — a Claude-
// free Fusion import path via Autodesk's ParameterIO add-in
// (Utilities → ParameterIO → Import). Plain text like features.json, so
// it gets the same default (level 6) compression, not `storedLevel`
// (that's reserved for the already-compressed JPEG/PNG face entries).
let buildZipBytes = (
  ~featuresJson: string,
  ~parametersCsv: string,
  ~faces: array<faceBundle>,
): Uint8Array.t => {
  let entries: Fflate.entries = Dict.make()
  Dict.set(entries, "features.json", (Fflate.encodeUtf8(featuresJson), Fflate.defaultLevel))
  Dict.set(entries, "parameters.csv", (Fflate.encodeUtf8(parametersCsv), Fflate.defaultLevel))
  faces->Array.forEach(fb => {
    Dict.set(entries, zipEntryPath(fb.label, ~suffix=".jpg"), (fb.original, Fflate.storedLevel))
    Dict.set(
      entries,
      zipEntryPath(fb.label, ~suffix="_dimensioned.png"),
      (fb.dimensioned, Fflate.storedLevel),
    )
  })
  Fflate.zipSync(entries)
}

let fileNameFor = (~slug: string): string => slug ++ ".ccpart.zip"

type outcome = Shared | Downloaded(string)
type error = ShareCancelled | Failed(string)

// SPEC M5 bullet 2: share when the platform can take files, else fall back
// to the download anchor. `navigator.canShare` existing isn't enough on
// its own — it also has to say yes to *this* file (SPEC: "If
// navigator.canShare exists and canShare({files: [zip]}) is true").
let deliver = async (
  ~zipBytes: Uint8Array.t,
  ~fileName: string,
  ~shareTitle: string,
): result<outcome, error> => {
  let file = Share.makeZipFile(zipBytes, ~fileName)
  if Share.hasShare() && Share.canShareFile(file) {
    try {
      await Share.share(file, ~title=shareTitle)
      Ok(Shared)
    } catch {
    | e if Share.isAbortError(e) => Error(ShareCancelled)
    | _ => Error(Failed("Share failed"))
    }
  } else {
    Share.downloadFile(file, ~fileName)
    Ok(Downloaded(fileName))
  }
}
