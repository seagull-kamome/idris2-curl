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

## Where the capture stream itself lives: `rc2base`, not here

`open_memstream(3)` and its own bookkeeping/read-back machinery have
nothing to do with libcurl specifically -- any C API with a
"write to this `FILE *`" option could use the same trick. So the
implementation lives in `idris2-rc-cg`'s own `rc2base` library as
`System.IO.MemStream` (`support/c/memstream.c`/`.h`,
`src/System/IO/MemStream.idr`), not in this repo's own `csrc/`.
`Network.Curl.Raw` consumes it purely as a client -- nothing in this
library's own public API mentions `MemStream` at all; see the next
section.

`System.IO.MemStream`'s own shims follow this project's usual "one
shim per accessor, no output pointer crosses into Idris" convention:
`idris2rc2_memstream_open`/`_filep`/`_close`/`_data`/`_size`/`_free`,
each operating on one small `malloc`'d bookkeeping struct wrapping the
`FILE *`/`buf`/`len` `open_memstream` itself hands back.

## Hidden behind three `curlEasyPerformTo*` functions

`Network.Curl.Raw` exposes `curlEasyPerformToBuffer`/`ToString`/
`ToTextBuffer` -- each opens a `MemStream`, points
`CURLOPT_WRITEDATA` at it, calls `curl_easy_perform`, closes the
stream, reads the captured body into its own target representation,
frees the stream, and returns `Maybe (CURLcode, <representation>)`.
A caller never sees `MemStream`, `CURLOPT_WRITEDATA`, or the capture
mechanism at all -- just "perform this transfer, get the body back as
a `Buffer`/`String`/`TextBuffer`." `Nothing` only if the capture
stream itself couldn't even be set up (allocation/`open_memstream(3)`/
setopt failure -- `curl_easy_perform` is never attempted then) or the
final read failed; a `curl_easy_perform` failure of its own still
comes back as `Just (code, body)`, whatever body there is, since a
caller who only cares about success already has the `CURLcode` to
check.

## Three target representations, one copy each

`rc2base`'s `System.IO.MemStream` module offers three `to*`
conversions off the same captured bytes, each independently one copy
(no chaining one conversion through another):

- **`toBuffer`**: `Buffer` (`Data.Buffer`, base library) has no public
  raw-pointer-fill API, only a byte-at-a-time `setBits8` (an FFI call
  per byte -- not a real memcpy). Idris2's own `Buffer` is
  `{int size; char data[];}` at the C level on both RefC
  (`idris2-src/support/refc/buffer.h`) and rc2
  (`rc2/support/rc2/buffer.h`, explicitly "ported from RefC's
  support/refc/buffer.c", "operates purely on the raw malloc'd
  buffer") -- deliberately identical, so
  `idris2rc2_memstream_copy_into_buffer` reinterprets a `Buffer`
  reaching it as that same struct and `memcpy`s the captured bytes in
  directly, one shim, one copy, exact byte count (embedded-NUL-safe,
  `Buffer`'s whole reason for existing here). Not reachable from Chez,
  whose own `Buffer` has no matching C struct at all (`blodwen-buffer-*`
  operates on a Scheme-native bytevector).

- **`toString`**: reuses `Data.String.FFI.ptrToString` (`rc2base`) as
  is -- already a single NUL-terminated raw-pointer read via
  `Prelude.IO`'s own `prim__getString`/`prim__castPtr`, no new code
  needed. Safe here because `open_memstream(3)` always NUL-terminates
  its own buffer on `fclose` (the NUL isn't counted in `len`) --
  truncates only if the response body itself contains an embedded NUL
  byte, the same pre-existing caveat every other `String`-returning
  binding in this library already has.

- **`toTextBuffer`**: `rc2base`'s `Data.TextBuffer` only offered
  `fromString : String -> TextBuffer` -- going through it would mean a
  second, redundant copy (raw bytes -> String -> TextBuffer). But
  `idris2rc2_String_to_TextBuffer` (the C function `fromString` itself
  calls) only ever sees a plain `const char *` at the ABI level, since
  an Idris `String` %foreign argument is already passed to C as a raw,
  NUL-terminated `char *` -- no marshalling step in between.
  `Data.TextBuffer.fromRawUtf8` (`rc2base`) binds that *same* C symbol
  directly against `AnyPtr` instead, decoding straight from the raw
  captured bytes with no new C code and no intermediate `String` --
  guarded by a `Data.So` proof (`NonNullPtr`) that the pointer isn't
  NULL, obtained via `Data.So.choose` at the one call site
  (`MemStream.toTextBuffer`) that has to check anyway, rather than
  left as a doc-comment precondition a caller could skip.
  `Data.TextBuffer`'s own implementation needs rc2's own runtime
  headers (`rc2/datatypes.h`, via `text_util.h`), so unlike everything
  else in this file, it isn't buildable against real upstream RefC at
  all -- `curlEasyPerformToTextBuffer` and `examples/GetCaptureText.idr`
  are rc2-only, split out from `examples/GetCapture.idr` (RefC/rc2,
  `Buffer`/`String` only) for that reason.

## Build note: `rc2base` needs its own `-l`/`-L` under plain RefC

`System.IO.MemStream`'s own `%foreign` declarations name
`libidris2rc2base` as their library -- `rc2`'s own `Compiler.RC2.CC`
derives `-l<lib>` from that automatically, but plain upstream
`idris2 --cg refc` doesn't (same gap as `-lcurl` itself, see
`doc/const-char-ffi.md`'s own "Linker caveat"), so
`IDRIS2_LDLIBS`/`IDRIS2_LDFLAGS` need `-lidris2rc2base`/
`-L<rc2base's own installed lib dir>` set by hand there. See
`AGENT.md`'s own "Build & test" section.
