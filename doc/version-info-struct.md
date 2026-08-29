# Binding `curl_version_info`: a real C struct, RefC/rc2-only

`curl_version_info(CURLVERSION_NOW)` returns
`curl_version_info_data *` -- a real C struct with ~20 fields
(`curl/curl.h`: version strings, a numeric version, a feature bitmask,
SSL/libz/etc. version strings, `NULL`-terminated string arrays for
supported protocols/feature names, ...), not a scalar `%foreign` can
hand back directly.

## Why not `System.FFI`'s `Struct`/`getField`

Idris2 has a purpose-built mechanism for exactly this: `System.FFI`'s
`Struct`/`getField`/`setField`. Not used here because it doesn't work
across all three backends this repo targets -- **Chez supports it, but
upstream RefC doesn't** (`rc2/doc/c-struct-support.md`'s own "What's
confirmed" section: `getField`/`setField` compile cleanly under plain
RefC but fail at the C-compile step, since RefC's own generated code
calls a `getField`/`setField` runtime helper that plain
`support/refc/` never defines; only `rc2`'s own later addition
implements it, with a regression test). Binding `curl_version_info`
through `Struct`/`getField` would work on Chez and rc2 but not plain
`idris2 --cg refc` -- accepted as a real gap for now (see this repo's
own "RefC で構造体関係で動かないのは許容します" decision), but not
worth reaching for on a first pass when the shim approach below
already covers Chez/RefC/rc2 uniformly for the fields actually needed.

## The fix: one shim per field, RefC/rc2-only

`csrc/idris2curl_compat.h` holds one `static inline` shim per field
actually used, each calling `curl_version_info(CURLVERSION_NOW)`
itself and reading straight off the result:
```c
static inline char *idris2curl_version_info_version(void) {
    const char *v = curl_version_info(CURLVERSION_NOW)->version;
    return (char *) (v == NULL ? "" : v);
}
```
`curl_version_info(CURLVERSION_NOW)` itself returns a pointer to a
static, library-owned struct (never freed, never reallocated) -- so
calling it once per shim, per field read, is cheap and never
invalidates any earlier shim's own return value; no need to cache it
on the Idris side.

Same "static inline, only a real symbol under static linking" argument
as `doc/const-char-ffi.md`/`doc/variadic-getinfo.md` applies here too:
no plain `"C:..."` target exists for any of these, so there's no Chez
binding at all -- confirmed the same way (type-checks fine, fails
cleanly with "was not accepted by any backend" only at
`examples/VersionInfo.idr`'s own actual call sites under Chez).

## Fields bound so far

`version` (`const char *`), `version_num` (`unsigned int`), `host`
(`const char *`), `features` (`int` bitmask -- test against
`curl/curl.h`'s own `CURL_VERSION_*` bit flags), `ssl_version`
(`const char *`). Not bound: `libz_version`, the `protocols`/
`feature_names` `NULL`-terminated string arrays (no Idris-side
array-of-`CFString` binding exists yet, and would need its own design
-- a `List String` return isn't something `%foreign` can express
directly either), and every field added after `CURLVERSION_FIRST`
(`ares`, `libidn`, `libssh_version`, `brotli_version`, ...) -- add a
shim + `Network.Curl.Raw` binding pair for any of these as a concrete
need comes up, same as `Network.Curl.Types`'s own `curlinfo_*`/
`curlopt_*` constants.

## String fields that can genuinely be `NULL`: raw pointer + `ptrToString`, not `""`-substitution

`version`/`host` above always substitute `""` for a `NULL` field at the
C-shim level -- fine, since libcurl always sets both. `ssl_version`
doesn't hold that guarantee: per `curl_version_info(3)`, it's `NULL`
whenever libcurl was built without SSL support, not merely an empty
string. Substituting `""` there would silently conflate "no SSL
backend" with a name that's empty (never actually happens, but the
distinction is the whole point of the field). So
`idris2curl_version_info_ssl_version` hands back the raw pointer
unchanged instead (`csrc/idris2curl_compat.h`), and
`Network.Curl.Raw`'s own `curlVersionInfoSslVersion` reads it through
`Data.String.FFI.ptrToString` (`rc2base`'s cross-backend, non-owning
`AnyPtr -> Maybe String` read -- see that module's own doc comment,
and `curlUrlGet`/`curlSlistToList` for the same tool used elsewhere),
returning `Maybe String` rather than `String`.

This is the house pattern for any *future* struct-field string read
too: prefer a raw-pointer shim + `ptrToString` on the Idris side over
`""`-substitution in C, whenever the field's own `NULL` genuinely means
something the shim shouldn't discard -- reach for the `""`-substitution
shortcut only when the field is documented as always-set (`version`/
`host` here), same judgement call already made for both of them.
