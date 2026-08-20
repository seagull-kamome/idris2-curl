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

Bound so far, enough to drive a synchronous `curl_easy` GET request:
`curl_global_init`, `curl_global_cleanup`, `curl_easy_init`,
`curl_easy_cleanup`, `curl_easy_setopt` (string- and long-valued
options), `curl_easy_perform`, `curl_easy_strerror`. See
`src/Network/Curl/Raw.idr` for the full list and
`src/Network/Curl/Types.idr` for the `CURLoption`/`CURLcode` constants
currently defined.

More of libcurl's own API surface (multi handle, callbacks/write
functions, more options) gets added incrementally as needed.

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
