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
  rc2base`; `rc2base` -- `idris2-rc-cg`'s own shared RefC/rc2 runtime
  helper library, checked out as a sibling repo -- is the one
  exception to an otherwise dependency-free design, needed for
  `Data.String.FFI.ptrToString`'s cross-backend `AnyPtr -> Maybe
  String` read, see `curlUrlGet`'s own doc comment)
- `src/Network/Curl/Types.idr` — `CURLcode`/`CURLoption` wrapper
  records and hand-written constants (no `%runElab` deriving)
- `src/Network/Curl/Raw.idr` — direct `%foreign "C:curl_*,libcurl,curl/curl.h"`
  declarations, one per bound libcurl function
- `csrc/` — small C shims a binding needs beyond a plain `%foreign`
  declaration (currently `idris2curl_compat.h`, see `doc/`)
- `examples/` — small standalone programs that exercise the bindings
  end to end, used to verify they build/link/run on Chez, upstream
  RefC, and `idris2-rc-cg`'s `rc2` backend -- except `GetInfo.idr`,
  `UrlGet.idr`, `VersionInfo.idr`, `Multi.idr`, and `Header.idr`, which
  are RefC/rc2-only (see `doc/variadic-getinfo.md`/
  `doc/version-info-struct.md`/`doc/multi-interface.md`), and
  `GetInfoOfft.idr`, which is rc2-only (not even upstream RefC -- see
  `doc/variadic-getinfo.md`'s own `CURLINFO_OFF_T`/`Int64` section)
- `doc/` — implementation deep-dives, meant to let a future session
  regain context without re-deriving the design (currently:
  `const-char-ffi.md` for why a `const char *`-returning libcurl
  function needs a `csrc/` shim and three separate `%foreign` targets,
  one per backend; `variadic-getinfo.md` for why `curl_easy_getinfo`/
  `curl_url_get` have no Chez binding at all; `version-info-struct.md`
  for why `curl_version_info` (a real C struct, not a scalar) is bound
  via per-field `csrc/` shims rather than `System.FFI`'s own
  `Struct`/`getField`; `multi-interface.md` for the same output-pointer/
  no-Chez-binding reasoning applied to `curl_multi_*`;
  `int-width-pitfall.md` for why a negative/sentinel `Int` `%foreign`
  argument (e.g. `CURL_ZERO_TERMINATED`) isn't safe on this project's
  three backends -- `Int`'s own width differs by backend, and `Int64`
  isn't a portable fix either)
- `TODO.md` — open gaps and deferred design decisions (removed once
  implemented and documented elsewhere)

## サブエージェント
- ファイル調査、コードベース調査、定型実装はサブエージェントに移譲する。
- メインセッションは判断、設計、統合のみを残す。
- 調査結果はサマリーのみをメインセッションに返却させる。(全文蓄積は禁止)


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

現状は`examples/`の手動実行のみで、まだこの規模の`tests/verify.sh`は無い。
退行テストと呼べる本数が増えた時点で整備する。

## Build & test

Default Chez backend (needs `rc2base` on the package path -- checked
out as a sibling `idris2-rc-cg` repo, installed per its own
`libs/rc2base/tests/verify.sh`):
```sh
export IDRIS2_PACKAGE_PATH="../idris2-rc-cg/libs/rc2base/.local-install/idris2-0.8.0"
idris2 --build package.ipkg
```

To build `examples/*.idr` against the library (rather than the plain
Chez backend above, which only type-checks `package.ipkg` itself),
install the library into a local prefix first -- the default Idris2
package location lives in a read-only nix store here. `csrc/` (see
below) must be on the include path for every backend:
```sh
export IDRIS2_PACKAGE_PATH="../idris2-rc-cg/libs/rc2base/.local-install/idris2-0.8.0"
IDRIS2_PREFIX="$(pwd)/.local-install" idris2 --install package.ipkg
export IDRIS2_CFLAGS="-Icsrc"
IDRIS2_PREFIX="$(pwd)/.local-install" idris2 -p curl -p rc2base -o get examples/Get.idr
```
`examples/GetInfo.idr` is RefC/rc2-only -- it has no Chez `%foreign`
target at all (`doc/variadic-getinfo.md`) and fails to build here.

Against plain upstream `idris2 --cg refc` (needs `IDRIS2_LDLIBS` set
by hand -- rc2's own automatic `-l<lib>` derivation, see below, hasn't
been upstreamed):
```sh
export IDRIS2_CFLAGS="-Icsrc"
export IDRIS2_LDLIBS="$(pkg-config --libs libcurl)"
IDRIS2_PREFIX="$(pwd)/.local-install" idris2 --cg refc -p curl -p rc2base -o get_refc examples/Get.idr
```

Against `idris2-rc-cg`'s rc2 backend (requires that repo checked out
as a sibling directory, its own `env.sh` sourced, `rc2base` installed
per its own `libs/rc2base/tests/verify.sh`, and `libcurl`/`curl.h`
available, e.g. via `nix-shell -p curl`):
```sh
source ../idris2-rc-cg/env.sh
export IDRIS2_PACKAGE_PATH="$IDRIS2_PACKAGE_PATH:$(pwd)/.local-install/idris2-0.8.0:../idris2-rc-cg/libs/rc2base/.local-install/idris2-0.8.0"
export IDRIS2_CFLAGS="-Icsrc -I../idris2-rc-cg/libs/rc2base/.local-install/idris2-0.8.0/rc2base-0.1.0/lib -I../idris2-rc-cg/install/idris2-0.8.0/support"
export IDRIS2_LDFLAGS="$(pkg-config --libs-only-L libcurl) -L../idris2-rc-cg/libs/rc2base/.local-install/idris2-0.8.0/rc2base-0.1.0/lib"
../idris2-rc-cg/rc2/build/exec/idris2-rc2 --cg rc2 -p curl -p rc2base -o get_rc2 examples/Get.idr
```
`-lcurl` itself no longer needs `IDRIS2_LDLIBS` set by hand under rc2
-- see `doc/const-char-ffi.md`'s own "Linker caveat" section for the
full story. Only the `-L` search path above (nix's libcurl isn't on
the linker's default path) and, at *run* time, `LD_LIBRARY_PATH`
pointing at the same directory are still needed by hand under either
static backend.

See `doc/const-char-ffi.md` for why `curl_easy_strerror` (and any
future `const char *`-returning binding) needs `csrc/`'s own shim and
three separate `%foreign` targets, one per backend, and
`doc/variadic-getinfo.md` for why `curl_easy_getinfo` has no Chez
binding at all.

## Conventions

- Code, comments, and commit messages: English.
- Never modify git config. Set identity inline per-commit only:
  `git -c user.name="..." -c user.email="..." commit ...`.
- Only commit when the user explicitly asks.
- ドキュメントを読めばわかる事はコードのコメントには書かず、参照リンクの記載に留める。
