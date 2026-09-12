# Binding `curl_version_info`: a real C struct, rc2-only

`curl_version_info(CURLVERSION_NOW)` returns
`curl_version_info_data *` -- a real C struct with ~25 fields
(`curl/curl.h`: version strings, a numeric version, a feature bitmask,
SSL/libz/etc. version strings, `NULL`-terminated string arrays for
supported protocols/feature names, ...), not a scalar `%foreign` can
hand back directly.

## `Struct`/`getField`, via `%cg rc2 externStruct=curl_version_info_data`

Idris2 has a purpose-built mechanism for exactly this: `System.FFI`'s
`Struct`/`getField`/`setField`, and rc2 implements it
(`idris2-rc-cg`'s `rc2/doc/c-struct-support.md`). This module's own
`VersionInfoPtr` (`Network.Curl.Raw`) uses it directly:

```idris2
%cg rc2 externStruct=curl_version_info_data

VersionInfoPtr : Type
VersionInfoPtr = Struct "curl_version_info_data"
    [ ("version", String), ("version_num", Int), ... ]
```

## Why this needed a dedicated rc2 directive first

Tried directly against `curl_version_info_data` once already, and
rejected at the time, for a reason unrelated to backend coverage:
**rc2 used to unconditionally emit its own `typedef struct { ... }
name;` for every struct name mentioned in a `Struct "name" [...]`**
(`c-struct-support.md`'s own Part C). For a struct a *library header
already defines* -- `curl_version_info_data` is `typedef`'d by
`curl/curl.h`, included via this same `%foreign` declaration's own
header field -- that collided outright:
```
error: conflicting types for 'curl_version_info_data'
```
confirmed directly at the time by compiling exactly that. The fix
landed in `idris2-rc-cg` itself, not here: `%cg rc2
externStruct=<name>` (repeatable, `rc2/doc/directives.md` section 5)
tells `Emit.idr`'s `header` to skip emitting its own typedef for a
listed name, while leaving `getField`/`setField`'s own field-type
table untouched -- `curl_version_info_data`'s real definition, already
visible via `curl/curl.h`'s own `#include`, is what the generated
`((curl_version_info_data*)ptr)->field` expression actually compiles
against.

One consequence worth calling out: with `externStruct`, the field
*order* in `VersionInfoPtr`'s own list is no longer load-bearing for
correctness (unlike a struct this repo would define and lay out
itself, `c-struct-support.md`'s own `Test24CStructSupport`) -- the
real `curl/curl.h` struct's own field order/width governs the actual
`->field` member access; the Idris list only has to name a field
correctly and give a C-type-compatible `CFType` for the value that
comes back. The version of this doc written *before* `externStruct`
existed worried about exactly this (hand-replicating field
order/width for a differently-named "view" struct) -- moot now, since
this binding never declares its own competing layout at all.

## `getField` doesn't scale to a wide struct -- confirmed by an actual OOM crash

Binding every non-array field (~24 of them) was tried first, replacing
`VersionInfoPtr`'s own 5-entry list with the full field list and
`curlVersionInfo` with one `getField`/`ptrToString` pair per field.
Compiling that (plain `idris2 --build package.ipkg`, Chez target --
`getField`'s own elaboration doesn't depend on the codegen backend)
**crashed the compiler itself**: `out of memory`, SIGABRT, confirmed
with a `ulimit -v 6000000` (6GB) cap in place first specifically to
stop it from taking down the whole machine again after an unbounded
first attempt already had. Not a slow-but-eventually-fine build --
genuinely unbounded memory growth during elaboration. Root cause not
pinned down further (not yet bisected to find the actual field-count
threshold) -- upstream `System.FFI`'s own `getField` implementation
almost certainly doesn't scale well with the `Struct`'s own field-list
length, given `curl_version_info_data`'s 5-field predecessor binding
compiled fine and every other `Struct` in this codebase or rc2's own
test suite (`Test24CStructSupport`, 2 fields) is far narrower.

**Consequence**: `VersionInfoPtr` only binds the same 5 fields the
pre-`Struct` shim design already had --
`version`/`version_num`/`host`/`features`/`ssl_version` -- not the
full struct. `age` and every field added after `CURLVERSION_FIRST`
(`libz_version`, `ares`, `libidn`, `brotli_*`, `nghttp2_*`,
`quic_version`, `cainfo`/`capath`, `zstd_*`, `hyper_version`,
`gsasl_version`, `rtmp_version`) are NOT bound, on top of
`protocols`/`feature_names` (`const char * const *`, `NULL`-terminated
arrays -- no Idris-side array-of-`CFString` binding exists either way)
and `ssl_version_num` (`curl/curl.h`'s own comment: "not used anymore,
always 0"). Adding any one of the unbound fields back is cheap
mechanically (one more `Struct` list entry, one more `getField` call --
no C code) but should be done a field or two at a time with an actual
build in between, not in one large batch, until the real threshold is
known.

`version`/`host` are the only two fields libcurl always sets
(`curl_version_info(3)`), so they're plain `String`. `ssl_version` is
typed `AnyPtr` in `VersionInfoPtr` and read through
`Data.String.FFI.ptrToString` in `curlVersionInfo` (`Network.Curl.Raw`)
rather than collapsed to `""` -- it's `NULL` whenever libcurl was built
without SSL support, and collapsing that to `""` would silently
conflate "no SSL backend" with a (never actually occurring) empty
version string. The same reasoning would apply to any future `const
char *` field added back in.

## `curl_header` (curl/header.h): same typedef collision, not switched yet

`curl_easy_header`/`curl_easy_nextheader`'s own `struct curl_header`
result is still read via a one-shim-per-field pair
(`idris2curl_header_name`/`_value`, `csrc/idris2curl_compat.h`), the
same design this struct used before. `%cg rc2
externStruct=curl_header` would work the same way, but hasn't been
done -- see `TODO.md`'s own entry for why (smaller payoff: only
`name`/`value` are exposed today).

## `CURLMsg`: still not a candidate

`doc/multi-interface.md` covers this in full: `CURLMsg`'s own `data`
field is a real C `union`, which `getField` has no `CFType` for at
all -- a different, structural problem `externStruct` doesn't touch.
