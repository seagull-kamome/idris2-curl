# Binding a `const char *`-returning C function across two backends

`curl_easy_strerror` (and any future libcurl function with the same
shape) returns `const char *`. rc2's own `%foreign` lowering hardcodes
`CFString` as non-const `char *` (`cTypeOfCFType CFString = "char *"`
in `Compiler.RC2.Emit`), so a direct binding's generated call site
```c
char * retVal = curl_easy_strerror(...);
```
collides with rc2's own `-Werror` (`-Wdiscarded-qualifiers`).

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
avoiding a real call, just the cast. This only works under rc2's own
statically-linked backend -- the shim is never a real symbol in
`libcurl.so`'s own dynamic-load table, so Chez's own
`load-shared-object`/`dlsym`-style lookup would fail with `no entry for
"idris2curl_easy_strerror"` if it ever tried to use it. Chez therefore
keeps calling `curl_easy_strerror` directly.

Each such binding declares *two* `%foreign` targets so the right one
gets picked automatically:
```idris2
%foreign "C:curl_easy_strerror,libcurl,curl/curl.h"
         "RC2:idris2curl_easy_strerror,libcurl,idris2curl_compat.h"
prim__curlEasyStrerror : Int -> PrimIO String
```
- rc2's own FFI tags are `["RC2", "RefC", "C"]` (`Compiler.RC2.Emit`'s
  own `ffiTags`, checked in that order), so `"RC2:..."` wins there.
- Chez's own target list (`["scheme,chez", "scheme", ..., "C"]`)
  matches neither and falls through to the plain `"C:..."` entry.

See `Network.Curl.Raw`'s own `prim__curlEasyStrerror` for the concrete
pattern to follow for any future `const char *`-returning binding.

## Linker caveat: `-lcurl` is automatic under rc2

rc2 derives `-l<lib>` automatically from every `%foreign`'s own lib
field (`Compiler.RC2.CC`'s own `compileCFile` -- fixed in
`idris2-rc-cg` after this repo's own experiment surfaced the gap), so
no `IDRIS2_LDLIBS`/`LDLIBS` is needed by hand for `-lcurl` itself under
rc2 -- only the `-L` search path (nix's libcurl isn't on the linker's
default path) and, at run time, `LD_LIBRARY_PATH` pointing at the same
directory.
