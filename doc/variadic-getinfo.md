# Binding `curl_easy_getinfo`/`curl_url_get`: variadic or output-pointer, RefC/rc2-only

`curl_url_get` (`curl/urlapi.h`) shares this same "no Chez binding at
all" conclusion for a related but distinct reason: it isn't variadic,
but its own third argument is a `char **` output pointer
(`idris2curl_url_get`, `csrc/idris2curl_compat.h`, collapses it to a
plain return value the same way the shims below do) -- `%foreign`
can pass a pointer *in*, but there's no way to read a value *back*
out of one afterward without a further FFI call, which the `static
inline` shim provides but Chez's own dynamic FFI can't reach (same
"real symbol under static linking only" constraint explained below).
Everything below is written in terms of `curl_easy_getinfo`, but the
"no Chez target, fails cleanly at the call site" reasoning applies to
`curl_url_get` identically.

`curl_easy_getinfo`'s own real C signature is
`CURLcode curl_easy_getinfo(CURL *curl, CURLINFO info, ...)` -- a
write-through output pointer whose *type* depends on which `CURLINFO`
is passed, via a runtime convention (`CURLINFO_STRING`/`_LONG`/
`_DOUBLE`/... tag bits on the enum value itself), not anything
`%foreign` can express directly.

## The fix: per-type shims, collapsing the output pointer to a return value

`csrc/idris2curl_compat.h` holds three shims --
`idris2curl_getinfo_long`, `idris2curl_getinfo_string`,
`idris2curl_getinfo_double` -- each hiding its own `long`/`char *`/
`double` output variable and returning it directly:
```c
static inline long idris2curl_getinfo_long(CURL *h, int info) {
    long v = 0;
    curl_easy_getinfo(h, (CURLINFO) info, &v);
    return v;
}
```
`curl_easy_getinfo`'s own `CURLcode` result is discarded -- acceptable
for now since every `CURLINFO` this repo currently binds
(`Network.Curl.Types`'s own `curlinfo_*` constants) is always
retrievable once `curl_easy_perform` has returned, per
`curl_easy_getinfo(3)`'s own contract. Revisit if a future `CURLINFO`
doesn't hold that (e.g. one that's genuinely optional depending on
what the transfer actually did).

## No Chez binding at all -- deliberately

Unlike `curl_easy_strerror` (see `doc/const-char-ffi.md`), there's no
plain `"C:..."` `%foreign` target for these at all: Chez can't call
`curl_easy_getinfo` directly either (its own dynamic FFI has no way to
express "the third argument's own pointee type depends on the second
argument's own value"), and can't reach the `static inline` shims (only
real symbols under static linking, per `doc/const-char-ffi.md`'s own
reasoning -- same argument applies here).

Confirmed directly (not just inferred) that this fails cleanly rather
than breaking every Chez build of the library: a `%foreign` with only
`"RefC:..."`/`"RC2:..."` targets still *type-checks* fine under Chez
(`idris2 --build package.ipkg` never needs to pick a target for a
declaration that's never actually called), and only errors -- with a
clear "was not accepted by any backend" message -- at the specific
call site of a program that's actually compiled against Chez. So
`Network.Curl.Raw`'s own `prim__curlEasyGetinfoLong`/`*String`/
`*Double` simply have no `"C:..."` entry; `examples/GetInfo.idr`
(the one place that calls them) is RefC/rc2-only by construction, not
included in Chez's own examples build. See `AGENT.md`'s own "Build &
test" section.

## Bound `CURLINFO` values

`Network.Curl.Types` currently defines `curlinfo_EFFECTIVE_URL`,
`curlinfo_RESPONSE_CODE`, `curlinfo_TOTAL_TIME`,
`curlinfo_NAMELOOKUP_TIME`, `curlinfo_CONNECT_TIME`,
`curlinfo_HEADER_SIZE`, `curlinfo_REQUEST_SIZE`,
`curlinfo_CONTENT_TYPE`, `curlinfo_REDIRECT_COUNT`
(`CURLINFO_STRING`/`_LONG`/`_DOUBLE`-tagged), plus one representative
each for the three remaining tags: `curlinfo_SIZE_DOWNLOAD_T`
(`_OFF_T`), `curlinfo_COOKIELIST` (`_SLIST`), `curlinfo_ACTIVESOCKET`
(`_SOCKET`). `off_t` is represented as `Int64` (`curl_off_t` is always
a real 64-bit signed integer in libcurl itself, independent of the
host platform's own `long` width) and `curl_socket_t` as plain `Int`
(a real C `int` on every non-Windows platform, per curl/curl.h's own
typedef) -- see `Network.Curl.Raw`'s own `curlEasyGetinfoOfft`/
`curlEasyGetinfoSocket` doc comments.

`CURLINFO_OFF_T`-tagged infos are rc2-only, unlike every other tag
here: confirmed directly that real upstream RefC's own C backend
crashes lowering any `Int64`-returning `%foreign` call ("INTERNAL
ERROR: Unknown FFI type in C backend: Int_64") against the
nixpkgs-packaged idris2 build used here, even though
`Compiler.RefC.RefC`'s own `cTypeOfCFType`/`extractValue`/`packCFType`
each do have a `CFInt64` case -- some other, unidentified stage still
fails to route it there. `examples/GetInfoOfft.idr` is rc2-only by
construction (not RefC/rc2 like every other example here) for this
reason; `examples/GetInfo.idr` itself exercises the `_SLIST`/`_SOCKET`
tags instead, both RefC-safe.

`CURLINFO_SLIST`'s own value (a `struct curl_slist *`) is read via
`Network.Curl.Raw`'s own `curlSlistToList`, one shim per field
(`idris2curl_slist_data`/`_next`) the same way `curl_version_info`/
`CURLMsg` are (see `version-info-struct.md`), with each node's own
`data` copied through `Data.String.FFI.ptrToString`'s bare (non-owning)
read -- ownership of every node's `data` belongs to the list as a
whole, released in one `curl_slist_free_all()` call
(`curlSlistFreeAll`), never per node.
