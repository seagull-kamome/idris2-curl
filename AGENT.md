# CLAUDE.md

This repo hosts **idris2-curl**, minimal, dependency-free libcurl FFI
bindings for Idris2. Written from scratch rather than porting
`MarcelineVQ/idris2-curl` (CC0): that package's `Derive.*` machinery
(`%runElab`-based enum/newtype/prim deriving) no longer compiles
against current Idris2's reflection API, and its option/error-code
types are woven through the whole public surface, making it
impractical to strip the deriving out and keep the rest. Every option/
error constant here is instead a hand-written value taken straight
from `curl/curl.h`. See `TODO.md` for open gaps and deferred design
decisions, `README.md` for the human-facing overview and current
binding status.

One goal of this repo is verifying that ordinary libcurl `%foreign`
calls actually build and run under `idris2-rc-cg`'s independent `rc2`
C codegen backend, not just the default Chez backend.

## Layout

- `package.ipkg` — library package (`depends = base, contrib,
  rc2base`; `rc2base` -- `idris2-rc-cg`'s own runtime helper library,
  checked out as a sibling repo -- supplies `Data.String.FFI.ptrToString`
  and the `System.IO.MemStream` body capture)
- `src/Network/Curl/Types.idr` — `CURLcode`/`CURLoption` wrapper
  records and hand-written constants (no `%runElab` deriving)
- `src/Network/Curl/Raw.idr` — direct `%foreign "C:curl_*,libcurl,curl/curl.h"`
  declarations and their `HasIO` wrappers. No C shim: output pointers
  and C structs go through `System.FFI.Struct`, see
  `doc/ffi-without-shims.md`
- `src/Network/Curl/Fetch.idr` — a JS `fetch()`-shaped convenience
  layer built on `Raw.idr` (`fetch`/`fetchBytes`/`fetchText`/`get`/
  `post`/`request`)
- `examples/` — small standalone programs using the bindings. Most
  talk to `example.com`, so they are run by hand, not by
  `tests/verify.sh`. All build on both backends; the body-capture ones
  (`GetCapture.idr`, `GetCaptureText.idr`, `Fetch.idr`) only run on
  rc2 (`doc/memstream-capture.md`)
- `tests/` — `verify.sh` plus network-free regression programs
  (`src/`), their expected output (`expected/`) and fixtures (`data/`)
- `doc/` — implementation deep-dives, meant to let a future session
  regain context without re-deriving the design:
  `ffi-without-shims.md` (how every binding avoids a C shim on both
  backends), `int-width-pitfall.md` (why a negative/sentinel `Int`
  `%foreign` argument such as `CURL_ZERO_TERMINATED` isn't safe on
  Chez), `memstream-capture.md` (capturing a response body without
  `CURLOPT_WRITEFUNCTION`)
- `TODO.md` — open gaps and deferred design decisions (removed once
  implemented and documented elsewhere)


## コーディング規約
以下を金言とせよ。

コードには How
テストコードには What
コミットログには Why
コードコメントには Why not

C言語用 ./code-style-C.md を参照
Idris2言語用 ./code-style-Idris2.md を参照

### コメント規約
コード内のコメントは極力排除する。
コード自体が何をしているか説明するような冗長なコメント(How)は禁止します。
どうしても必要場合は(Why not/特異な制約等)を除き、コメント無しのクリーンな
コードを書きなさい。

モジュールの先頭には、そのモジュールの役目と負うべき責任についてのコメントと
Copyright表記を書きなさい。

-- Copyright 2026, Hattori,Hiroki. All rights reserved.
-- This module was licensed by BSD3.


### テストコード

退行テスト、スモークテストの期待出力はあらかじめテキストファイルを作っておき、
diffのみで成否判定できるようにする。
全てのテストを順番に実行して成否判定するシェルスクリプト'tests/verify.sh'を用意する。
テストの実施はこのスクリプトで行い成否判定の手間を簡略化する。
新しいテストを作成したらスクリプトも更新する。
テストを単体で走らせる必要が生じた場合の手順はこのスクリプトを見ればわかるようにしておく。
テストの結果生じる生成物(生成したCコード、IRダンプ、テスト出力)はtests/build以下に
置きテスト終了時には消さずに後で確認できるように残しおく。このディレクトリはテストスクリプト
の先頭で掃除してからテストが実施されるようにしておく。

## Build & test

Run the tests with `tests/verify.sh` (it enters its own `nix-shell`).
It installs the library, then builds and runs each test in its `TESTS`
list on Chez and rc2 against `tests/expected/`. How to run a single test by
hand is in its header comment.

Every backend runs against `idris2-rc-cg`'s own self-built toolchain
(checked out as a sibling directory and built, `rc2base` included);
sourcing its `env.sh` puts that `idris2` first on `PATH`, and its
default prefix (`../idris2-rc-cg/install`) already holds `base`/
`contrib`/`rc2base` -- no `IDRIS2_PREFIX`/`IDRIS2_PACKAGE_PATH`
override is needed. Installing needs no libcurl; compiling an example
does (`nix-shell -p gcc gmp pkg-config curl`):
```sh
source ../idris2-rc-cg/env.sh
idris2 --install package.ipkg
export IDRIS2_LDFLAGS="$(pkg-config --libs-only-L libcurl)"
idris2 -p curl -p rc2base -o get examples/Get.idr
../idris2-rc-cg/rc2/build/exec/idris2-rc2 --cg rc2 -p curl -p rc2base -o get_rc2 examples/Get.idr
```
Run the result with `LD_LIBRARY_PATH="$(pkg-config --variable=libdir
libcurl)"` -- nix's libcurl isn't on the default runtime search path.
rc2 derives `-lcurl` from the `%foreign` lib field itself, so only the
`-L` path above is needed.

Build rc2 and Chez in separate `--build-dir`s (as `verify.sh` does): a
plain `idris2` build drops any `%cg rc2` directive and leaves a TTC
that a later rc2 build would reuse.

## Conventions

- Code, comments, and commit messages: English.
- Never modify git config. Set identity inline per-commit only:
  `git -c user.name="..." -c user.email="..." commit ...`.
- Only commit when the user explicitly asks.
- ドキュメントを読めばわかる事はコードのコメントには書かず、参照リンクの記載に留める。
