# idris2-curl

Minimal libcurl FFI bindings for Idris2, depending on nothing but `base`
and `contrib`, so a plain Idris2 (Chez) installation can use them.
Targets Chez and `idris2-rc-cg`'s `rc2` backend -- upstream RefC
support was dropped as unneeded overhead for this project.

Two packages:
- **`curl`** (`package.ipkg`) is the bindings themselves, for both
  backends.
- **`curl-rc2`** (`curl-rc2.ipkg`) adds `Network.Curl.TextBuffer`,
  body capture into rc2base's `TextBuffer`. It depends on rc2base,
  whose installation needs the rc2 toolchain, so it is only for rc2
  users.

## Why this exists

[`MarcelineVQ/idris2-curl`](https://github.com/MarcelineVQ/idris2-curl)
(CC0) already exists, but its `Derive.*` machinery
(`%runElab`-based enum/newtype/prim deriving) no longer compiles
against current Idris2's reflection API, and that machinery is woven
through the whole public surface -- stripping it out and keeping the
rest wasn't practical. This repo binds the same handful of `curl_easy_*`
functions from scratch instead, with every option/error-code constant
a hand-written value taken straight from `curl/curl.h`, no deriving at
all.

A second goal: verifying that ordinary libcurl `%foreign` calls
actually build, link, and run under
[`idris2-rc-cg`](https://github.com/seagull-kamome/Idris2-rc2)'s
independent `rc2` C codegen backend -- not just the default Chez
backend Idris2 ships with.

## Status

Bound so far, enough to drive a synchronous `curl_easy` GET request
with custom headers, inspect the result, and parse/build URLs:
`curl_global_init`, `curl_global_cleanup`, `curl_easy_init`,
`curl_easy_cleanup`, `curl_easy_setopt` (string-, long-, and
slist-valued options), `curl_easy_perform`, `curl_easy_strerror`,
`curl_easy_duphandle`, `curl_easy_reset`, `curl_easy_getinfo`
(every `CURLINFO` type), `curl_slist_append`, `curl_slist_free_all`,
`curl_easy_escape`, `curl_easy_unescape`, `curl_free`, `curl_version`,
`curl_version_info` (the `CURLVERSION_FIRST` fields), the `curl_url_*`
URL API, and enough of
the `curl_multi_*` interface to drive several concurrent transfers to
completion on one thread, a shared DNS/session
cache across easy handles (`curl_share_*`), multipart form uploads
(`curl_mime_*`), pausing/keepalive (`curl_easy_pause`/
`curl_easy_upkeep`), and the structured header API
(`curl_easy_header`/`curl_easy_nextheader`). Everything works on both
backends with no C shim of its own (`doc/ffi-without-shims.md`),
except capture into a `TextBuffer` (`curl-rc2`, see "Limitations"). See
`src/Network/Curl/Raw.idr` for the
full list and `src/Network/Curl/Types.idr` for the `CURLoption`/
`CURLcode`/`CURLINFO`/`CURLUcode`/`CURLUPart` constants currently
defined.

Being implemented incrementally, working through libcurl's own public
API surface roughly in order of practical usefulness. See `TODO.md`
for the current list of gaps (callback options like
`CURLOPT_WRITEFUNCTION`, the multi/share/mime interfaces, and
smaller easy-interface gaps).

## `Network.Curl.Fetch` -- a JS `fetch()`-shaped convenience layer

`src/Network/Curl/Fetch.idr` wraps the raw bindings above into
`fetch : FetchRequest -> io (Either FetchError FetchResponse)` (plus
`fetchBytes`/`fetchText`/`get`/`post`/`request`) -- one function call
per request, no `curl_global_init`/`curl_easy_init`/setopt/`curl_slist`
bookkeeping of your own. Works on both backends. `examples/Fetch.idr` exercises it end to end.

## Backends

Verified end-to-end (a real HTTP GET against `example.com`) on:

- The default Chez backend (`idris2`)
- `idris2-rc-cg`'s `rc2` backend

`tests/verify.sh` runs the network-free regression tests on both.

## Limitations

- **Capture into a `TextBuffer` is rc2-only**, in the separate
  `curl-rc2` package: `Data.TextBuffer` is an rc2 runtime type. Use
  `curlEasyPerformToString`/`ToBuffer` on Chez.
- **Upstream RefC is not supported.** `const char *` returns such as
  `curl_easy_strerror` fail its `-Werror` build.
- **A captured handle keeps `CURLOPT_WRITEDATA` on a closed stream.**
  Set it again (or reset the handle) before performing on that handle
  without capture.
- **Bodies of 2 GiB or more can't be captured into a `Buffer` on
  Chez**, where the copy length is a 32-bit C `int`.
- **No callback options** (`CURLOPT_WRITEFUNCTION`,
  `CURLOPT_HEADERFUNCTION`, ...); see `TODO.md`.

Details: `doc/memstream-capture.md`, `doc/int-width-pitfall.md`.

## Building

```sh
idris2 --build package.ipkg
```

builds and type-checks the library itself against the default Chez
backend. See `AGENT.md`'s own "Build & test" section for building
`examples/*.idr` against the library on either backend above.

## License

BSD3, per each module's own copyright header.

## See also

- `AGENT.md` — repo layout, coding conventions, build instructions
- `doc/` — implementation deep-dives for specific design decisions
- `TODO.md` — open gaps and deferred design decisions
