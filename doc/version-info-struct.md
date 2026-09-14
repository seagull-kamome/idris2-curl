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

## `curl_header` (curl/header.h): converted, full 6-field list, on purpose

`curl_easy_header`/`curl_easy_nextheader`'s own `struct curl_header`
result used to be read via a one-shim-per-field pair
(`idris2curl_header_name`/`_value`, `csrc/idris2curl_compat.h`), the
same design `curl_version_info_data` used before. Switched to `%cg rc2
externStruct=curl_header` + `Struct`/`getField` (`Network.Curl.Raw`'s
own `HeaderPtr`), same mechanism as `VersionInfoPtr`/`SlistPtr` above.

Unlike `curl_slist`, this repo only ever *reads* two of the real
struct's six fields (`name`/`value` -- `curl/header.h`: `{ char *name;
char *value; size_t amount; size_t index; unsigned int origin; void
*anchor; }`). Binding only those two in `HeaderPtr`'s own field list
would repeat `VersionInfoPtr`'s exact unsafe-on-Chez situation (a
from-scratch Chez `define-ftype` computed from a partial field list
diverges from the real struct's own offsets past the point a field was
skipped) -- and unlike `curl_slist` (whose only reader,
`prim__curlEasyGetinfoSlist`, stays `"RC2:..."`-only, so a Chez build
can never actually reach the unsafe path), `curl_easy_nextheader` has
a real `"C:..."` target reachable from Chez today (only
`curl_easy_header` itself is rc2-only, for the unrelated output-
pointer-collapse reason `doc/variadic-getinfo.md` covers). So
`HeaderPtr` lists all six real fields, in the real struct's own
order and with width-correct types (`Bits64` for the two `size_t`
fields, `Bits32` for the `unsigned int` one -- confirmed against
`idris2-rc-cg`'s own `cTypeOfCFType`, which maps those to `uint64_t`/
`uint32_t`) even though `amount`/`index`/`origin`/`anchor` are never
read by `getField` anywhere -- they exist purely to keep a
from-scratch Chez layout correct, same reasoning as `curl_slist`'s own
full-field-list section above, just for real this time since the
reachability gap is real here. `anchor` in particular is `curl/header.h`'s
own "handle privately used by libcurl" field -- never meant to be read
by a caller at all, bound here for layout only.

Considered and rejected: inserting a separate no-op dummy `%foreign`
declaration purely to keep `curl_header` "registered" regardless of
which real producer a future caller happens to use, addressing the
different (reachability, not layout) gotcha `SlistPtr`'s own doc
comment describes. Unnecessary here -- both real producers
(`prim__curlEasyHeader` and `prim__curlEasyNextheader`) are now typed
`HeaderPtr` themselves, so each one independently registers
`curl_header` with rc2 whenever *it* is reachable, without relying on
the other. Since a caller cannot read a `curl_header`'s fields at all
without first obtaining one from one of these two functions, real
usage can never reach `getField` without also making at least one of
them reachable -- a dummy anchor would only earn its keep in a design
where the struct-producing call and the struct-reading call could be
reached independently, which isn't the shape of this API.

## `curl_slist`: converted, and the one case where Chez isn't ruled out

`struct curl_slist` (`curl/curl.h`: `{ char *data; struct curl_slist
*next; }`) used to read its two fields via `idris2curl_slist_data`/
`_next` (`csrc/idris2curl_compat.h`), the same one-shim-per-field
design `curl_version_info_data` used before. Switched to `%cg rc2
externStruct=curl_slist` + `Struct`/`getField` (`Network.Curl.Raw`'s
own `SlistPtr`) instead, same mechanism as `VersionInfoPtr` above.

This case differs from `VersionInfoPtr` in the one respect that
mattered for the "Chez's own `Struct`/`getField` computes its own
`define-ftype` from the field list, not the real header's own layout"
caveat above: `SlistPtr`'s field list is the *entire* real struct, in
its *real declaration order* (`data` then `next`), not a 5-of-25
subset. A Chez-synthesized `define-ftype` from that exact list is
therefore byte-for-byte identical to the real `struct curl_slist`
layout -- no skipped/reordered field to make its offsets diverge from
libcurl's own. Not actually exercised on Chez either way yet, though:
`curlSlistToList` (the only reader of these two fields) was already
unreachable from Chez before this change, since `prim__curlSlistData`/
`_next`'s old `%foreign` declarations had `"RC2:..."` targets only, no
Chez fallback -- this conversion doesn't change that, `SlistPtr`
itself is a plain type-level `Struct` alias, not backend-gated. Should
someone bind a Chez-reachable use of `curlSlistToList` later, verify
this reasoning against an actual run before trusting it, same as
everything else in this doc.

A real gotcha confirmed while doing this conversion, worth calling out
separately: rc2's `RStructGet` codegen only learns a struct's layout
from an actual `%foreign` declaration typed with it, and only if that
declaration stays *reachable* in the specific compiled program after
dead-code elimination -- not merely declared at module scope.
`SlistPtr` itself has no `%foreign` of its own; `prim__curlEasyGetinfoSlist`
(retyped to return `SlistPtr`, then cast back to `AnyPtr` in its own
`curlEasyGetinfoSlist` wrapper, purely to be that registration point)
is the only place in `Network.Curl.Raw` that does. A throwaway test
program that only called `curlSlistAppend`/`curlSlistToList` -- never
`curlEasyGetinfoSlist` -- failed with `INTERNAL ERROR: [rc2]
RStructGet: unknown struct curl_slist` even with `SlistPtr` declared
right there in the same module; adding one real call to
`curlEasyGetinfoSlist` into that same program fixed it. Every real
caller of `curlSlistToList` in this repo already goes through
`curlEasyGetinfoSlist` first (`GetInfo.idr`'s own COOKIELIST read), so
this doesn't bite today -- but keep it in mind if `curl_slist` reading
is ever reached some other way.

## `CURLMsg`: still not a candidate

`doc/multi-interface.md` covers this in full: `CURLMsg`'s own `data`
field is a real C `union`, which `getField` has no `CFType` for at
all -- a different, structural problem `externStruct` doesn't touch.
