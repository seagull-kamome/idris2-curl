---
name: run-idris2-curl
description: Build idris2-curl (minimal libcurl FFI bindings for Idris2), install it locally, and compile+run a network-free example against the Chez, RefC, and/or rc2 backends. Use when asked to build idris2-curl, run/test it, compile an example against it, or verify the bindings still link and run on any backend.
---

`idris2-curl` is a library, not an app — "running" it means building
it, installing it into a local package prefix, and compiling one of
`examples/*.idr` against it on a real backend, then running the
resulting native binary. Drive it via
`.claude/skills/run-idris2-curl/smoke.sh`, which does exactly that
for `examples/UrlAndEscape.idr` (the one example that needs no
outbound network access) and checks its output.

All paths below are relative to `idris2-curl/` (the unit root, i.e.
this repo).

**Do not use `examples/Get.idr` or the other network-hitting examples**
(`GetInfo.idr`, `GetWithHeaders.idr`, `Header.idr`, `Multi.idr`,
`ShareAndMime.idr`, `UrlGet.idr`) for automated verification — they
make a real HTTP request to `example.com`, which an agent sandbox's
network allowlist typically doesn't permit. `UrlAndEscape.idr` only
exercises `curl_version`/`curl_easy_escape`/`curl_easy_unescape`/
`curl_url_*`, all local.

## Prerequisites

Everything is pulled in per-command via `nix-shell -p ...` (idris2,
gcc, gmp, pkg-config, curl) — nothing to install ahead of time beyond
`nix` itself being on `PATH`. The `rc2` backend additionally needs
`idris2-rc-cg` checked out and built as a sibling directory
(`../idris2-rc-cg`) — see that repo's own `run-idris2-rc-cg` skill.

## Setup

No manual setup step — `smoke.sh` builds and locally installs the
library itself (`IDRIS2_PREFIX="$(pwd)/.local-install"`, gitignored).

## Build

```bash
nix-shell -p idris2 gcc gmp pkg-config curl --run 'idris2 --build package.ipkg'
```

Type-checks the library against the default Chez backend only. To
actually compile an example against it, the library must also be
installed to a local prefix first (the default install location is a
read-only nix store path here):

```bash
nix-shell -p idris2 gcc gmp pkg-config curl --run \
  "IDRIS2_PREFIX='$(pwd)/.local-install' idris2 --install package.ipkg"
```

`smoke.sh` does both of the above automatically.

## Run (agent path)

```bash
.claude/skills/run-idris2-curl/smoke.sh                # Chez only (default, fastest)
.claude/skills/run-idris2-curl/smoke.sh --backend=refc  # upstream idris2 --cg refc
.claude/skills/run-idris2-curl/smoke.sh --backend=rc2   # idris2-rc-cg's rc2 backend
.claude/skills/run-idris2-curl/smoke.sh --backend=all   # all three, in order
```

Each run type-checks + installs the library, compiles
`examples/UrlAndEscape.idr` against the chosen backend(s) into
`build/exec/smoke_urlget_<backend>`, runs it with `LD_LIBRARY_PATH`
pointed at nix's `libcurl.so`, and checks the output against the
known-good `curl_version: libcurl/...` / `escaped: a%20b%2Fc%3Fd` /
`unescaped: a b/c?d` lines. Exit 0 + `== smoke test OK ==` means the
bindings actually link and run on that backend, not just type-check.

## Run (human path)

To try one of the network-hitting examples by hand (needs real
outbound HTTP, so only do this outside a sandboxed agent run):

```bash
export IDRIS2_CFLAGS="-Icsrc"
IDRIS2_PREFIX="$(pwd)/.local-install" idris2 -p curl -o get examples/Get.idr
nix-shell -p gcc gmp curl pkg-config --run \
  'export LD_LIBRARY_PATH="$(pkg-config --variable=libdir libcurl):${LD_LIBRARY_PATH:-}"; ./build/exec/get'
```

## Test

No `tests/verify.sh` yet (per `AGENT.md`: too few regression tests so
far to justify one) — `smoke.sh --backend=all` above is the closest
thing to a test suite today.

## Gotchas

- **Running a compiled binary without `LD_LIBRARY_PATH` set fails**
  with `Exception: (while loading libcurl.so) libcurl.so: cannot open
  shared object file` — nix's libcurl isn't on the default linker
  search path at runtime, even though it links fine at build time via
  `pkg-config --libs-only-L`. Always run compiled binaries with
  `LD_LIBRARY_PATH="$(pkg-config --variable=libdir libcurl):$LD_LIBRARY_PATH"`
  (`smoke.sh` does this).
- **Omitting `-p curl` (or `IDRIS2_CFLAGS=-Icsrc`)** when compiling an
  example produces module-not-found or missing-header errors — both
  are required every time, on every backend, they're not implied by
  the library install step.
- **The `rc2` backend path is a relative sibling-directory reference**
  (`../idris2-rc-cg/rc2/build/exec/idris2-rc2`) — if that repo hasn't
  been built yet, `smoke.sh --backend=rc2` fails fast with a clear
  message pointing at its own run skill, rather than a cryptic "file
  not found."
- **`examples/Get.idr` (and the other network-hitting examples) will
  hang or fail under a sandboxed agent** with no outbound HTTP to
  `example.com` — use `UrlAndEscape.idr` (what `smoke.sh` uses) for
  any automated check.
