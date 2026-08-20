# idris2-curl

Minimal, dependency-free libcurl FFI bindings for Idris2.

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
(string/long/double `CURLINFO`s -- RefC/rc2 only, see
`doc/variadic-getinfo.md`), `curl_slist_append`, `curl_slist_free_all`,
`curl_easy_escape`, `curl_easy_unescape`, `curl_free`, `curl_version`,
`curl_version_info` (five fields -- RefC/rc2 only, see
`doc/version-info-struct.md`), the `curl_url_*` URL API (`curl_url_get`
is RefC/rc2 only, same reason as `curl_easy_getinfo`), and enough of
the `curl_multi_*` interface to drive several concurrent transfers to
completion on one thread (`curl_multi_perform`/`_wait`/`_info_read` are
RefC/rc2 only, see `doc/multi-interface.md`). See
`src/Network/Curl/Raw.idr` for the
full list and `src/Network/Curl/Types.idr` for the `CURLoption`/
`CURLcode`/`CURLINFO`/`CURLUcode`/`CURLUPart` constants currently
defined.

Being implemented incrementally, working through libcurl's own public
API surface roughly in order of practical usefulness. See `TODO.md`
for the current list of gaps (callback options like
`CURLOPT_WRITEFUNCTION`, `curl_version_info`, the multi/share/mime
interfaces, smaller easy-interface gaps, and a couple of deliberately
accepted small memory leaks).

## Backends

Verified end-to-end (a real HTTP GET against `example.com`) on:

- The default Chez backend (`idris2`)
- Upstream RefC (`idris2 --cg refc`)
- `idris2-rc-cg`'s `rc2` backend

A `const char *`-returning function like `curl_easy_strerror` needs
backend-specific handling to build cleanly on the two statically-linked
backends -- see `doc/const-char-ffi.md`.

## Building

```sh
idris2 --build package.ipkg
```

builds and type-checks the library itself against the default Chez
backend. See `AGENT.md`'s own "Build & test" section for building
`examples/*.idr` against the library on any of the three backends
above (local installation, include/link flags, etc.).

## License

BSD3, per each module's own copyright header.

## See also

- `AGENT.md` — repo layout, coding conventions, build instructions
- `doc/` — implementation deep-dives for specific design decisions
- `TODO.md` — open gaps and deferred design decisions
