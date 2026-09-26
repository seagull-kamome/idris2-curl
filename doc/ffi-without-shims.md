# Binding libcurl without a C shim

Every libcurl function this library binds is a plain `%foreign "C:..."`
declaration against `curl/curl.h`. There is no C file of our own, so
installing the package needs no libcurl at all and a consumer needs no
extra `-I` path. The same declarations serve both supported backends
(Chez and `idris2-rc-cg`'s rc2). This page explains the four
techniques that make that possible, and why each obvious alternative
was not used.

Up to 2026-09 the library carried `csrc/idris2curl_compat.h`, a header
of 18 `static inline` wrappers. Being `static inline`, they never
existed in `libcurl.so`, so Chez could not call them. Every function
behind one (getinfo, `curl_url_get`, the multi interface,
`curl_easy_header`, `curl_version_info`) was therefore rc2-only. All of
them now work on both backends.

## 1. `const char *` returns bind directly

`curl_easy_strerror` and friends return `const char *`. rc2 used to
declare every `String` return as `char *`, and `-Werror
-Wdiscarded-qualifiers` rejected the direct binding. rc2 now maps
`CFString` to `const char *` (`Emit/Util.idr`'s `cTypeOfCFType`), so
the shims are gone.

The strerror bindings are pure (`CURLcode -> String`) via
`unsafePerformIO`, the same as base's `System.Errno.strerror`. Each one
returns a pointer to a static string. `System.Errno.strerror` itself
can't stand in for them: it formats libc `errno` values, while
`CURLcode` is a separate numbering (6 is "Could not resolve hostname"
to libcurl but `ENXIO` to libc).

## 2. Output pointers are `Struct` cells

`curl_easy_getinfo`, `curl_url_get`, `curl_multi_perform`/`_wait`/
`_info_read` and `curl_easy_header` all return a value through a
pointer argument. We pass them a one-field `System.FFI.Struct`, such as
`Struct "idris2curl_cell_i64" [("v", Int64)]`, and read it back with
`getField`.

These calls are variadic (`curl_easy_getinfo`) or take a typed pointer
(`char **`, `int *`). Both accept the cell: rc2 passes a `Struct` as a
pointer, and Chez passes its ftype pointer's address.

**The cell must come from a `%foreign` call whose return type is the
`Struct`.** We bind libc `malloc` once per cell type:

```idris
%foreign "C:malloc,libc,stdlib.h"
prim__newCellI64 : Int -> PrimIO CellI64
```

Chez represents a `Struct` as an ftype pointer, and only a foreign
return typed as the `Struct` gets wrapped into one. Two alternatives
crash with "invalid memory reference" on Chez, because each hands it a
bare integer address:
- `System.FFI.malloc` followed by `believe_me`;
- a `Buffer`.

A `Buffer` has a second problem on rc2: it is passed as its `char *`
data. That is fine for a variadic callee but fails `-Werror` against a
typed `char **` parameter.

**Field widths follow the C type, not Idris's `Int`.** On Chez, a
`Struct` field typed `Int` is a 32-bit C `int` (see
`int-width-pitfall.md`). So:

| C output type | Cell field type |
|---|---|
| `long` | `Int64` |
| `curl_off_t` | `Int64` |
| `int` counts | `Int32` |
| `curl_socket_t` | `Int32` |
| `double` | `Double` |
| pointer | `AnyPtr` |

The wrapper then casts the value to `Int` where the public API wants
one.

The getinfo wrappers now return `Either CURLcode a`. The old shims
discarded libcurl's result code and returned a default value instead.

## 3. C structs are read through our own `Struct` views

`curl_slist`, `curl_header`, `CURLMsg` and `curl_version_info_data` are
read with `getField` on a `Struct` that carries **our own name**. Each
field list is the real C layout, in order: rc2 and Chez both lay the
`Struct` out from that list with ordinary C alignment.

| View | Real struct | Fields listed |
|---|---|---|
| `idris2curl_slist` | `struct curl_slist` | both |
| `idris2curl_header` | `struct curl_header` | all six |
| `idris2curl_msg` | `CURLMsg` | `msg`, `easy_handle`, and the union read as its low 32 bits (`result`, little-endian only) |
| `idris2curl_version_info` | `curl_version_info_data` | the prefix from `age` to `ssl_version` (a prefix is enough, since we only read) |

String fields are declared `AnyPtr` and read with a local `ptrToString`
(upstream's `prim__getString`), because Chez's `define-ftype` has no
`string` field type ("unrecognized ftype name string").

Why not use libcurl's own names with rc2's `%cg rc2
externStruct=<name>`, as before? Three reasons:

- `curl_slist` and `curl_header` are bare struct tags with no typedef,
  so `curl_header*` doesn't even compile.
- Chez still needs the full field list to build its ftype, so
  `externStruct`'s "field order is irrelevant" advantage is lost
  anyway.
- A `%cg rc2` directive is dropped, with an "Unknown code generator
  rc2" warning, whenever the module is checked by a plain `idris2`.
  That includes `idris2 --install`, and the resulting TTC then lacks
  the directive for every later rc2 build.

## 4. Viewing an `AnyPtr` as a `Struct`: `memset(p, 0, 0)`

A function that may return NULL (`curl_easy_nextheader`,
`curl_multi_info_read`), or the list walk in `curlSlistToList`, needs
the pointer as an `AnyPtr` first, to test it with `prim__nullAnyPtr`.
Only after that test can it be read as a struct view. Chez gives no way
to test an ftype pointer for NULL from Idris, and `believe_me` from an
`AnyPtr` doesn't produce an ftype pointer (section 2).

So a non-NULL `AnyPtr` is turned into a view by calling libc `memset`
with length 0. That call writes nothing and returns its first argument,
through a `%foreign` return typed as the view:

```idris
%foreign "C:memset,libc,string.h"
prim__viewHeader : AnyPtr -> Int -> Int -> PrimIO HeaderView
```

It is only ever called on a pointer already known to be non-NULL.

## What is still rc2-only

Only `curl-rc2`'s `curlEasyPerformToTextBuffer`, because `Data.TextBuffer` is an rc2
runtime type. Body capture otherwise binds libc's `open_memstream`
directly, so `String`/`Buffer` capture and `Network.Curl.Fetch` work on
Chez too (`memstream-capture.md`).

## Tests

`tests/verify.sh` compiles each `tests/src/*.idr` on both backends and
diffs the output against `tests/expected/`. Nothing in it needs outbound
network:
- the transfers use `file://`;
- the header and status-code test uses a `python3 -m http.server` bound
  to 127.0.0.1.

Between them the tests exercise:
- every cell type;
- every struct view;
- the `memset` cast;
- a getinfo error return;
- the strerror bindings.
