// Fflate — typed surface over the `fflate` package for the export bundle
// (SPEC §5 dependency note, §7 bundle layout, M5 bullet 2). The only
// dependency this module adds beyond what's installed; nothing else without
// asking (CLAUDE.md).
//
// fflate's real `zipSync(data: Zippable, opts?)` accepts, per entry, either
// a plain `Uint8Array` or a `[Uint8Array, ZipOptions]` tuple — the tuple's
// options are merged over (and take precedence over) the call's top-level
// options (verified against the installed package's source: `fltn` does
// `op = mrg(o, val[1])` when the entry is an array). A ReScript 2-tuple
// `(Uint8Array.t, zipOptions)` compiles to exactly that `[data, opts]` JS
// array, so passing options on *every* entry — explicit `{level: 6}` for
// text, `{level: 0}` for the already-compressed JPEG/PNG entries — gives a
// fully typed binding with no raw-shape branching and no reliance on a
// separate "global default" parameter.

type zipOptions = {level: int}

// fflate's own default (see its DeflateOptions doc: "The default level is
// 6"), spelled out so a caller never has to guess what omitting it would do.
let defaultLevel: zipOptions = {level: 6}
// Already-compressed JPEG/PNG bytes: re-deflating them wastes CPU for a
// negligible size win, so these entries are stored, not compressed.
let storedLevel: zipOptions = {level: 0}

type entries = Dict.t<(Uint8Array.t, zipOptions)>

@module("fflate") external zipSync: entries => Uint8Array.t = "zipSync"

// -- text → bytes -----------------------------------------------------------
//
// `features.json` is produced as a ReScript string (FeaturesDocument.make);
// this is the one DOM-adjacent step needed to hand it to `zipSync` as bytes.
// TextEncoder always encodes UTF-8, matching JSON.stringify's output.

type textEncoder
@new external makeTextEncoder: unit => textEncoder = "TextEncoder"
@send external encodeText: (textEncoder, string) => Uint8Array.t = "encode"

let encodeUtf8 = (s: string): Uint8Array.t => encodeText(makeTextEncoder(), s)
