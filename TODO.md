# TODO

Open gaps and deferred design decisions. Entries get removed once
implemented and documented elsewhere (a `doc/*.md`, a doc comment) --
this file stays the changelog/gap tracker, not a duplicate of either.

## Not bound yet: libcurl's own callback options

Any `CURLOPT_*FUNCTION` option (`CURLOPT_WRITEFUNCTION`,
`CURLOPT_HEADERFUNCTION`, `CURLOPT_READFUNCTION`, ...) needs passing an
Idris function to C as a function pointer. `System.FFI` has no support
for this out of the box -- deliberately deferred rather than worked
around; the eventual approach is a single fixed C-side callback handing
data to Idris over a `Chan`, not an FFI closure trick.

For the common "capture the whole response body" case specifically,
`CURLOPT_WRITEFUNCTION` itself turns out not to be necessary --
`CURLOPT_WRITEDATA` (an ordinary object-pointer option) pointed at an
`open_memstream(3)` `FILE *` redirects libcurl's own *default* writer
into memory with no callback at all. See `doc/memstream-capture.md` and
`Network.Curl.Raw`'s own `curlEasyPerformToBuffer`/`ToString`/
`ToTextBuffer` -- the capture stream itself is `rc2base`'s own
`System.IO.MemStream` (nothing curl-specific about `open_memstream`),
never exposed in this library's own public API. Still open:
`CURLOPT_HEADERFUNCTION`/`CURLOPT_READFUNCTION` and genuinely streaming
(rather than capture-then-read) body handling, which do need a real
callback.

## `curl_multi_*` coverage is a minimal working subset

Bound: `curl_multi_init`/`_cleanup`/`_add_handle`/`_remove_handle`/
`_perform`/`_wait`/`_info_read`/`_strerror` -- enough to drive multiple
concurrent transfers to completion on one thread (see
`doc/multi-interface.md`, `examples/Multi.idr`). Not bound:
`curl_multi_setopt` (multi-handle options -- e.g. max concurrent
connections -- none needed yet), `curl_multi_fdset`/
`curl_multi_socket_action` (the older/lower-level polling APIs
`curl_multi_wait` already covers this repo's own needs instead of),
`curl_multi_assign`/`curl_multi_get_handles`/`curl_multi_get_offt`,
`curl_multi_waitfds`/`curl_multi_wakeup`/`curl_multi_notify_*`,
`curl_pushheader_byname`/`curl_pushheader_bynum` (server push, HTTP/2
only). Add as a concrete need comes up.

## `curl_share_*`/`curl_mime_*` coverage is a minimal working subset

Bound: `curl_share_init`/`_cleanup`/`_setopt` (`CURLSHOPT_SHARE`/
`_UNSHARE` only -- `_LOCKFUNC`/`_UNLOCKFUNC`/`_USERDATA` need a
callback, see above)/`_strerror`; `curl_mime_init`/`_free`/`_addpart`/
`_name`/`_filename`/`_type`/`_data`/`_filedata`/`_headers`. Fully bound
on both backends -- unlike most of Phase 1/2's own bindings,
nothing here needs an output-pointer/variadic-argument shim. Not
bound: `curl_mime_encoder`, `curl_mime_data_cb` (needs a callback),
`curl_mime_subparts` (nested multipart, no concrete need yet). Add as
a concrete need comes up.

## Smaller easy-interface gaps

Bound: `curl_easy_pause`/`curl_easy_upkeep` (fully bound on both
backends, no output-pointer trouble) and `curl_easy_header`/
`curl_easy_nextheader` (the structured header API -- rc2 only,
same `struct curl_header` output-pointer/field-access reasoning as
`CURLMsg`; see `Network.Curl.Raw`'s own doc comment on
`prim__curlEasyHeader`). `curl_easy_pause` itself is only meaningful
called from inside a transfer callback -- confirmed directly,
including with a bare C reproduction outside Idris, that calling it on
a handle in either of the only two states reachable without one
(before/after a transfer) always returns
`CURLE_BAD_FUNCTION_ARGUMENT`; `examples/PauseUpkeep.idr` documents
and expects this rather than treating it as a binding bug.

## `curl_header` (curl/header.h) could switch to `Struct`/`getField` like `curl_version_info_data`

`idris2curl_header_name`/`idris2curl_header_value` (`csrc/idris2curl_compat.h`)
still read `struct curl_header`'s own `name`/`value` fields through a
one-shim-per-field pair, the same design `curl_version_info_data` used
before switching to `System.FFI`'s `Struct`/`getField` (this repo's own
commit doing that -- see `doc/version-info-struct.md`). `%cg rc2
externStruct=curl_header` (idris2-rc-cg's rc2/doc/directives.md) would
sidestep the exact same `curl/header.h`-already-typedefs-it collision
`curl_version_info_data` had. Not done yet -- `curl_header` has fewer
fields (just `name`/`value`, plus `amount`/`index`/`origin` this repo
doesn't currently expose) so the payoff is smaller, but the mechanism
is identical. `CURLMsg` (`doc/multi-interface.md`) is NOT a candidate
for the same treatment -- its own `data` field is a real C `union`,
which `getField` has no `CFType` for at all, unrelated to the typedef-
collision problem `externStruct` solves.

Not bound: `curl_easy_recv`/`curl_easy_send` (raw socket access --
binary buffers, no concrete need yet), `curl_pushheader_byname`/
`curl_pushheader_bynum` (HTTP/2 server push only), `curl_easy_ssls_export`
(needs a callback)/`curl_easy_ssls_import` (binary session-ticket data,
no concrete need without being able to export first). None blocking
anything else, just not reached yet.

## `CURLINFO`/`CURLOPT` coverage is a small, hand-picked subset

`Network.Curl.Types` only defines the handful of `curlinfo_*`/
`curlopt_*` constants each `examples/*.idr` actually exercises.
libcurl has several hundred `CURLOPT_*` options and ~100 `CURLINFO_*`
values; add more as a concrete need comes up rather than
pre-emptively transcribing the whole enum. All six `CURLINFO_*` type
tags (`STRING`/`LONG`/`DOUBLE`/`SLIST`/`OFF_T`/`SOCKET`) now have a
matching `Network.Curl.Raw` `curlEasyGetinfo*` function and at least
one bound constant each -- `off_t` is represented as `Int64`
(`curl_off_t` is always a real 64-bit signed integer in libcurl
itself, independent of the host platform's own `long` width).


