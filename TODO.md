# TODO

Open gaps and deferred design decisions. Entries get removed once
implemented and documented elsewhere (a `doc/*.md`, a doc comment) --
this file stays the changelog/gap tracker, not a duplicate of either.

## Not bound yet: libcurl's own callback options

Any `CURLOPT_*FUNCTION` option (`CURLOPT_WRITEFUNCTION`,
`CURLOPT_HEADERFUNCTION`, `CURLOPT_READFUNCTION`, ...) needs passing an
Idris function to C as a function pointer. `System.FFI` has no support
for this out of the box, and it hasn't been investigated further --
deliberately deferred rather than worked around. Without it, a
response body can only go to libcurl's own default (stdout) or a
`FILE *` obtained some other way; there's no way yet to capture it into
an Idris `String`/`Buffer`.

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
on all three backends -- unlike most of Phase 1/2's own bindings,
nothing here needs an output-pointer/variadic-argument shim. Not
bound: `curl_mime_encoder`, `curl_mime_data_cb` (needs a callback),
`curl_mime_subparts` (nested multipart, no concrete need yet). Add as
a concrete need comes up.

## Smaller easy-interface gaps

Not bound: `curl_easy_pause`, `curl_easy_recv`/`curl_easy_send`
(raw socket access), `curl_easy_upkeep`, `curl_easy_header`/
`curl_easy_nextheader`/`curl_pushheader_byname`/`curl_pushheader_bynum`
(the newer structured header API), `curl_easy_ssls_export`/
`curl_easy_ssls_import`. None blocking anything else, just not reached
yet.

## `CURLINFO`/`CURLOPT` coverage is a small, hand-picked subset

`Network.Curl.Types` only defines the handful of `curlinfo_*`/
`curlopt_*` constants each `examples/*.idr` actually exercises.
libcurl has several hundred `CURLOPT_*` options and ~100 `CURLINFO_*`
values; add more as a concrete need comes up rather than
pre-emptively transcribing the whole enum. `CURLINFO_SLIST`/
`CURLINFO_OFF_T`/`CURLINFO_SOCKET`-tagged infos also need
`Network.Curl.Raw`'s own `curlEasyGetinfo*` extended with a matching
`idris2curl_getinfo_*` shim and Idris-side type before any concrete
`curlinfo_*` constant of that tag is worth adding --- `off_t` in
particular needs a representation decision (`Int` truncates on a
32-bit `long` platform; `Integer` is always safe but boxed).

## Deliberate small memory leaks: `curl_url_get`, `curl_easy_escape`/`curl_easy_unescape`

Every one of these hands back a libcurl-allocated string that's meant
to be released with `curl_free()` once read. `%foreign`'s own `String`
return already copies the bytes into a fresh Idris-owned string right
after the call returns, but nothing downstream of that copy gets a
chance to `curl_free()` the original -- there's no hook in a plain
`%foreign` call for "run this after the copy, before returning to
Idris code". See `idris2curl_url_get`'s own doc comment
(`csrc/idris2curl_compat.h`) for the full reasoning already recorded
there.

Accepted for now: one string's worth of leaked bytes per call (rarely
more than a few dozen), not unbounded, not accumulating per network
request. Revisit by splitting each into fetch/take/free step functions
coordinated from the Idris2 side (at the cost of thread-unsafe global
state in the shim) if a program ends up calling one of these often
enough for it to matter.

**Tried and rejected**: `System.FFI`/`Prelude.IO`'s own
`GCAnyPtr`/`onCollectAny` (attach a finalizer -- an ordinary Idris
`IO ()` action, e.g. one that calls `curl_free` -- to a raw pointer,
run automatically once the GC reclaims it) looked like a clean fix:
receive the raw `char *` as a plain `AnyPtr` instead of `String`,
`onCollectAny ptr (\p => primIO (prim__curlFree p))` to get a
`GCAnyPtr`, then a second `%foreign` declaration typed to take a
`GCAnyPtr` argument directly (`Compiler.RC2.Emit`/upstream
`RefC.idr`/`Compiler.Scheme.Chez` all implement `CFGCPtr`, unwrapping
it to the real pointer before the call) and read the string back
(e.g. `idris2_getString, libidris2_support, idris_support.h` retyped
from its own usual `Ptr String -> String` to `GCAnyPtr -> String`).

Confirmed directly this works correctly on Chez: the finalizer fires
strictly after the string copy, every time, across repeated runs.
**Confirmed directly this is broken on both RefC and rc2**: the
finalizer (`curl_free`) fires *before* the string-reading call
actually executes -- reproduced consistently across repeated runs on
both backends, reading back an empty string (RefC) or garbage bytes
(rc2) instead of the escaped/decoded text. Root cause not
pinned down further (not clear yet whether this is an rc2-specific
reference-counting bug or one inherited from upstream RefC's own
`CFGCPtr` handling -- both are reference-counted backends, unlike
Chez's own tracing GC, and the symptom looks like the `GCAnyPtr`
argument's own reference gets dropped -- and its finalizer run -- as
soon as it's evaluated for the call, not after the call itself
returns). Given this fails on two of this repo's three target
backends, not worth pursuing further over the accepted small leak
above unless a future session narrows down and fixes the underlying
drop-ordering bug.

## `curlUrlGet` can't distinguish "empty part" from "curl_url_get failed"

`idris2curl_url_get`'s own collapsed return (`csrc/idris2curl_compat.h`)
doesn't thread the underlying `CURLUcode` back to the Idris side --
both a `curl_url_get` failure and a part that's genuinely empty come
back as `""`. Not encountered in practice yet (every part
`examples/UrlGet.idr` reads is always present for the URLs tested), but
would need the shim reworked to return `(CURLUcode, String)` (e.g. via
an output-argument pointer of its own, or two shims) to fix properly.
