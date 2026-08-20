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

## Multi/share/mime interfaces not started

`curl_multi_*` (concurrent/non-blocking transfers), `curl_share_*`
(sharing state -- cookies, DNS cache, TLS session cache -- across
multiple easy handles), `curl_mime_*` (multipart form data) are
entirely unbound. Next in practical-usefulness order once callbacks
(above) are figured out, since multi-handle use is far more compelling
once a response body can actually be captured.

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

## `curlUrlGet` can't distinguish "empty part" from "curl_url_get failed"

`idris2curl_url_get`'s own collapsed return (`csrc/idris2curl_compat.h`)
doesn't thread the underlying `CURLUcode` back to the Idris side --
both a `curl_url_get` failure and a part that's genuinely empty come
back as `""`. Not encountered in practice yet (every part
`examples/UrlGet.idr` reads is always present for the URLs tested), but
would need the shim reworked to return `(CURLUcode, String)` (e.g. via
an output-argument pointer of its own, or two shims) to fix properly.
