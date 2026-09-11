# Binding `curl_version_info`: a real C struct, rc2-only

`curl_version_info(CURLVERSION_NOW)` returns
`curl_version_info_data *` -- a real C struct with ~20 fields
(`curl/curl.h`: version strings, a numeric version, a feature bitmask,
SSL/libz/etc. version strings, `NULL`-terminated string arrays for
supported protocols/feature names, ...), not a scalar `%foreign` can
hand back directly.

## Why not `System.FFI`'s `Struct`/`getField`

Idris2 has a purpose-built mechanism for exactly this: `System.FFI`'s
`Struct`/`getField`/`setField`, and rc2 now implements it
(`rc2/doc/c-struct-support.md`). Tried directly against
`curl_version_info_data` specifically and rejected, for a reason
unrelated to backend coverage: **rc2 unconditionally emits its own
`typedef struct { ... } name;` for every struct name mentioned in a
`Struct "name" [...]`** (`c-struct-support.md`'s own Part C). For a
struct a *library header already defines* -- `curl_version_info_data`
is `typedef`'d by `curl/curl.h`, included via this same `%foreign`
declaration's own header field -- that collides outright:
```
error: conflicting types for 'curl_version_info_data'
```
confirmed directly by compiling exactly that (a
`Struct "curl_version_info_data" [("version", String), ...]`
`%foreign` binding, real `curl/curl.h` included). A differently-named
"view" struct sidesteps the redefinition error, but only by hand-
replicating the real struct's own field layout (order *and* exact
width -- `curl_version_info_data`'s own leading `CURLversion age` is a
4-byte C enum, not `Int`'s 64-bit default on rc2; get one field's width
wrong and every later field's offset is silently off), for a struct
this repo doesn't own and libcurl could reorder or extend release to
release -- strictly more fragile than the one-shim-per-field approach
below, which lets the real `curl/curl.h` struct definition (via a real
C dereference, `%include`d) compute every offset instead of an Idris
programmer replicating them by hand. `getField`/`setField` remain the
right tool for a struct *this program defines itself* under a name
that appears nowhere else (`rc2/tests/Test24CStructSupport.idr`'s own
`test_point`) -- not for reflecting into an existing library's struct.

## The fix: one shim per field, rc2-only

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
`examples/VersionInfo.idr`'s own actual call sites under Chez), the
same gap `Struct`/`getField` would have hit for an unrelated reason
(see above) even if this were rewritten to use it.

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
