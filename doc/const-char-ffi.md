# Binding a `const char *`-returning C function across three backends

`curl_easy_strerror` (and any future libcurl function with the same
shape) returns `const char *`. Both rc2's and upstream RefC's own
`%foreign` lowering hardcode `CFString` as non-const `char *`
(`cTypeOfCFType CFString = "char *"` in `Compiler.RC2.Emit`/upstream's
`Compiler.RefC.RefC`), so a direct binding's generated call site
```c
char * retVal = curl_easy_strerror(...);
```
collides with either backend's own `-Werror`
(`-Wdiscarded-qualifiers`). Confirmed directly against both backends,
not inferred from one from reading the source: `idris2 --cg refc` on a
bare `curl_easy_strerror` binding fails with the identical error rc2
does.

Chez has no such issue -- dynamically typed, no C-level qualifier to
discard.

## The fix: a `static inline` shim, picked per backend

`csrc/idris2curl_compat.h` holds a `static inline` wrapper that
absorbs the cast explicitly:
```c
static inline char *idris2curl_easy_strerror(int code) {
    return (char *) curl_easy_strerror((CURLcode) code);
}
```
`static inline` rather than a real function: the whole point is
avoiding a real call, just the cast. This only works under a
statically-linked backend (rc2, upstream RefC) -- the shim is never a
real symbol in `libcurl.so`'s own dynamic-load table, so Chez's own
`load-shared-object`/`dlsym`-style lookup would fail with `no entry for
"idris2curl_easy_strerror"` if it ever tried to use it. Chez therefore
keeps calling `curl_easy_strerror` directly.

Each such binding declares *three* `%foreign` targets so the right one
gets picked automatically:
```idris2
%foreign "C:curl_easy_strerror,libcurl,curl/curl.h"
         "RefC:idris2curl_easy_strerror,libcurl,idris2curl_compat.h"
         "RC2:idris2curl_easy_strerror,libcurl,idris2curl_compat.h"
prim__curlEasyStrerror : Int -> PrimIO String
```
- Chez's own target list (`["scheme,chez", "scheme", ..., "C"]`)
  matches neither `"RefC"` nor `"RC2"` and falls through to the plain
  `"C:..."` entry.
- Plain upstream `idris2 --cg refc`'s own FFI tags are `["RefC", "C"]`,
  so `"RefC:..."` wins there.
- rc2's own FFI tags are `["RC2", "RefC", "C"]` (`Compiler.RC2.Emit`'s
  own `ffiTags`, checked in that order), so `"RC2:..."` wins there.

See `Network.Curl.Raw`'s own `prim__curlEasyStrerror` for the concrete
pattern to follow for any future `const char *`-returning binding.

## Linker caveat: `-lcurl` isn't automatic under plain RefC

Both static-linking backends need `-lcurl` reaching the linker. rc2
derives `-l<lib>` automatically from every `%foreign`'s own lib field
(`Compiler.RC2.CC`'s own `compileCFile` -- fixed in `idris2-rc-cg`
after this repo's own experiment surfaced the gap). Plain upstream
RefC doesn't have that fix, so building with `--cg refc` still needs
`IDRIS2_LDLIBS`/`LDLIBS` set by hand (e.g.
`IDRIS2_LDLIBS="$(pkg-config --libs libcurl)"`).
