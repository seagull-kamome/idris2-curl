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

`csrc/idris2curl_compat.h`'s `idris2curl_memstream_*` family wraps the
`FILE *`/`buf`/`len` `open_memstream` hands back in one small
`malloc`'d bookkeeping struct (`struct idris2curl_memstream`), read
via the usual "one shim per accessor, no output pointer crosses into
Idris" convention this file already uses everywhere else -- `_open`/
`_filep`/`_close`/`_data`/`_size`/`_free`. RefC/rc2-only, same "static
inline bookkeeping shim, no real symbol Chez's dynamic FFI can reach"
reasoning as most of this file -- not a fundamental limit of
`open_memstream` itself (a real, Chez-reachable libc symbol), just of
wrapping it here.

## Three target representations, one copy each

The user's own requirement: `Buffer` (bytes), `String` (UTF-8), and
`TextBuffer` (codepoints, `rc2base`'s `Data.TextBuffer`) all need to be
reachable from the captured bytes, and none of the three may cost more
than one copy -- no chaining one conversion through another.

- **`curlMemstreamToBuffer`**: `Buffer` (`Data.Buffer`, base library)
  has no public raw-pointer-fill API, only a byte-at-a-time
  `setBits8` (an FFI call per byte -- not a real memcpy). Idris2's own
  `Buffer` is `{int size; char data[];}` at the C level on both RefC
  (`idris2-src/support/refc/buffer.h`) and rc2
  (`rc2/support/rc2/buffer.h`, explicitly "ported from RefC's
  support/refc/buffer.c", "operates purely on the raw malloc'd
  buffer") -- deliberately identical, so
  `idris2curl_memstream_copy_into_buffer` reinterprets a `Buffer`
  reaching it as that same struct and `memcpy`s the captured bytes in
  directly, one shim, one copy, exact byte count (embedded-NUL-safe,
  `Buffer`'s whole reason for existing here). Not reachable from Chez,
  whose own `Buffer` has no matching C struct at all (`blodwen-buffer-*`
  operates on a Scheme-native bytevector).

- **`curlMemstreamToString`**: reuses `Data.String.FFI.ptrToString`
  (`rc2base`) as-is -- already a single NUL-terminated raw-pointer
  read via `Prelude.IO`'s own `prim__getString`/`prim__castPtr`, no
  new code needed. Safe here because `open_memstream(3)` always
  NUL-terminates its own buffer on `fclose` (the NUL isn't counted in
  `len`) -- truncates only if the response body itself contains an
  embedded NUL byte, the same pre-existing caveat every other
  `String`-returning binding in this library already has.

- **`curlMemstreamToTextBuffer`**: `rc2base`'s `Data.TextBuffer` only
  offered `fromString : String -> TextBuffer` -- going through it
  would mean a second, redundant copy (raw bytes -> String ->
  TextBuffer). But `idris2rc2_String_to_TextBuffer` (the C function
  `fromString` itself calls) only ever sees a plain `const char *` at
  the ABI level, since an Idris `String` %foreign argument is already
  passed to C as a raw, NUL-terminated `char *` -- no marshalling step
  in between. `Data.TextBuffer.fromRawUtf8` (`rc2base`) binds that
  *same* C symbol directly against `AnyPtr` instead, decoding straight
  from the raw captured bytes with no new C code and no intermediate
  `String`. `Data.TextBuffer`'s own implementation needs rc2's own
  runtime headers (`rc2/datatypes.h`, via `text_util.h`), so unlike
  everything else in this file, it isn't buildable against real
  upstream RefC at all -- `examples/GetCaptureText.idr` is rc2-only,
  split out from `examples/GetCapture.idr` (RefC/rc2, `Buffer`/`String`
  only) for that reason.

## Ownership

`curlMemstreamClose` must run once, after `curl_easy_perform` returns,
before any `curlMemstreamTo*`/`curlMemstreamSize` call (it's what
flushes/finalizes `buf`/`len`). `curlMemstreamFree` releases both the
bookkeeping struct and the captured buffer itself (plain `free()`, not
`curl_free()` -- `open_memstream`'s own buffer is a regular glibc
`malloc` allocation, unrelated to libcurl's own allocator) -- call it
once, after every read is done. None of the three `curlMemstreamTo*`
conversions take ownership of or free the memstream handle themselves.
