# Binding `curl_easy_getinfo`: variadic, RefC/rc2-only

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
`curlinfo_CONTENT_TYPE`, `curlinfo_REDIRECT_COUNT` -- every one
`CURLINFO_STRING`/`_LONG`/`_DOUBLE`-tagged. `CURLINFO_SLIST`/
`_OFF_T`/`_SOCKET`-tagged infos (e.g. `CURLINFO_SIZE_DOWNLOAD_T`,
`CURLINFO_COOKIELIST`) aren't bound yet -- would need their own
`idris2curl_getinfo_*` shim and Idris-side type (`off_t` in particular
needs a representation decision: `Int` truncates on a 32-bit `long`
platform, `Integer` is always safe but boxed).
