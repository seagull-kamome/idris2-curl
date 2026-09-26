# Capturing a response body without `CURLOPT_WRITEFUNCTION`

`CURLOPT_WRITEFUNCTION` itself is still not bound (see `TODO.md`'s own
"callback options" entry) -- passing an arbitrary Idris function to C
as a function pointer isn't something `%foreign` supports. Without
it, `curl_easy_perform`'s default write callback --
`fwrite(ptr, size, nmemb, (FILE *) CURLOPT_WRITEDATA)` -- writes the
response body straight to the process's real `stdout`, confirmed
directly: `examples/Get.idr` (which sets `CURLOPT_VERBOSE` but no
write callback) prints the HTML body on its own stdout, separate from
`CURLOPT_VERBOSE`'s own trace output on stderr.

## The fix: redirect the *default* writer, don't replace it

`CURLOPT_WRITEDATA` itself is an ordinary object-pointer option --
`curlEasySetoptPointer` already binds it, no callback of our own
needed. POSIX's `open_memstream(3)` hands back a `FILE *` backed by a
growable heap buffer instead of a real file descriptor; pointing
`CURLOPT_WRITEDATA` at that `FILE *` redirects libcurl's own existing
default writer into memory, with zero new callback machinery. This
only replaces the common "capture the whole body" case --
`CURLOPT_HEADERFUNCTION`/`CURLOPT_READFUNCTION`/streaming
`CURLOPT_WRITEFUNCTION` still need the real thing (a C-side fixed
callback handing data to Idris over a `Chan`, per this project's own
design note for when that's picked up).

## libc directly, not rc2base's `System.IO.MemStream`

The capture stream used to be rc2base's `System.IO.MemStream`, whose C
helpers live in rc2base's own support library (`libidris2rc2base.a`).
That tied capture, and with it `Network.Curl.Fetch`, to rc2. A Chez
program reaching it failed at start-up looking for
`libidris2rc2base.so`.

Building that library for Chez is not a fix. Someone compiling for Chez
need not have the rc2 toolchain that produces it.

Capture now binds libc itself, the same way on both backends:

| Step | Call |
|---|---|
| open the stream | `open_memstream(char **, size_t *)` |
| after the transfer | `fclose` |
| copy into a `Buffer` | `memcpy` |
| release the stream's memory | `free` |

`open_memstream`'s two output pointers are `Struct` cells
(`doc/ffi-without-shims.md`). `size_t` is read through an `Int64`
cell. A `Buffer` argument reaches C as its byte array on both
backends: rc2 passes the raw buffer's data, Chez a bytevector's. So
`memcpy` fills it directly.

## Three target representations, one copy each

`performCapture` runs the transfer and hands the reader the stream's
data pointer and length, both valid until it returns. Then it frees
the data.

- **`String`**: a local `ptrToString` over upstream Prelude's
  `prim__getString`. `open_memstream` always
  NUL-terminates, so this is one copy. An embedded NUL cuts the body
  short, as with every other `String`-returning binding here.
- **`Buffer`**: `newBuffer len`, then `memcpy`. This is one copy,
  exact, and NUL-safe.
- **`TextBuffer`**: `Data.TextBuffer.fromRawUtf8`, decoding the raw
  bytes in one copy. rc2-only: `Data.TextBuffer` is an rc2 runtime
  type, so this lives in the separate `curl-rc2` package
  (`Network.Curl.TextBuffer`), built on the exported
  `curlEasyPerformCapture`.

## Limitations

- **`curlEasyPerformToTextBuffer` is rc2-only** (`curl-rc2`). There
  is no `TextBuffer` on Chez, and rc2base needs the rc2 toolchain to
  install.
- **`CURLOPT_WRITEDATA` is left pointing at the closed stream.** A
  later `curlEasyPerform` on the same handle without capture would
  write to freed memory. Set `CURLOPT_WRITEDATA` again, or reset the
  handle, first. There is no `%foreign` way to name libc's `stdout`
  and restore the default.
- **Bodies of 2 GiB or more are not supported on Chez.** `memcpy`'s
  length is an `Int`, which is a 32-bit C `int` on Chez
  (`doc/int-width-pitfall.md`).
