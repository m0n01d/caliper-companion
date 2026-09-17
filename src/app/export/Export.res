// Export — M5 entry point. The Part page calls `run`; the export module owns
// everything behind it (dimensioned PNG render, zip, share/download).
//
// STUB: replaced by the M5 module. The signature is the contract.

type error =
  | KindConflict(string) // a feature name has mixed kinds; export is blocked (SPEC M5)
  | NoFaces // nothing to export yet
  | Failed(string) // anything else, user-readable

type outcome =
  | Shared // navigator.share({files}) completed
  | Downloaded(string) // fallback anchor download; the file name

let run = (_store: Store.t, ~partId as _partId: string, ~appVersion as _appVersion: string): promise<
  result<outcome, error>,
> => Promise.resolve(Error(Failed("Export is not implemented yet")))
