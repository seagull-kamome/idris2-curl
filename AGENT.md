# CLAUDE.md

This repo hosts **idris2-curl**, minimal, dependency-free libcurl FFI
bindings for Idris2. Written from scratch rather than porting
`MarcelineVQ/idris2-curl` (CC0): that package's `Derive.*` machinery
(`%runElab`-based enum/newtype/prim deriving) no longer compiles
against current Idris2's reflection API, and its option/error-code
types are woven through the whole public surface, making it
impractical to strip the deriving out and keep the rest. Every option/
error constant here is instead a hand-written value taken straight
from `curl/curl.h`.

One goal of this repo is verifying that ordinary libcurl `%foreign`
calls actually build and run under `idris2-rc-cg`'s independent `rc2`
C codegen backend, not just the default Chez backend.

## Layout

- `package.ipkg` — library package (`depends = base, contrib` only;
  deliberately no third-party dependency)
- `src/Network/Curl/Types.idr` — `CURLcode`/`CURLoption` wrapper
  records and hand-written constants (no `%runElab` deriving)
- `src/Network/Curl/Raw.idr` — direct `%foreign "C:curl_*,libcurl,curl/curl.h"`
  declarations, one per bound libcurl function
- `examples/` — small standalone programs that exercise the bindings
  end to end, used to verify they build/link/run on both the default
  Chez backend and `idris2-rc-cg`'s `rc2` backend

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

Default Chez backend:
```sh
idris2 --build package.ipkg
```

To build `examples/*.idr` against the library (rather than the plain
Chez backend above, which only type-checks `package.ipkg` itself),
install the library into a local prefix first -- the default Idris2
package location lives in a read-only nix store here. `csrc/` (see
below) must be on the include path for both backends:
```sh
IDRIS2_PREFIX="$(pwd)/.local-install" idris2 --install package.ipkg
export IDRIS2_CFLAGS="-Icsrc"
IDRIS2_PREFIX="$(pwd)/.local-install" idris2 -p curl -o get examples/Get.idr
```

Against `idris2-rc-cg`'s rc2 backend (requires that repo checked out
as a sibling directory, its own `env.sh` sourced, and `libcurl`/
`curl.h` available, e.g. via `nix-shell -p curl`):
```sh
source ../idris2-rc-cg/env.sh
export IDRIS2_PACKAGE_PATH="$IDRIS2_PACKAGE_PATH:$(pwd)/.local-install/idris2-0.8.0"
export IDRIS2_CFLAGS="-Icsrc"
export IDRIS2_LDFLAGS="$(pkg-config --libs-only-L libcurl)"
../idris2-rc-cg/rc2/build/exec/idris2-rc2 --cg rc2 -p curl -o get_rc2 examples/Get.idr
```
`-lcurl` itself no longer needs `IDRIS2_LDLIBS` set by hand -- rc2 now
derives `-l<lib>` flags straight from every `%foreign`'s own lib field
(fixed in `idris2-rc-cg` after this repo's own experiment surfaced the
gap). Only the `-L` search path above (nix's libcurl isn't on the
linker's default path) and, at *run* time, `LD_LIBRARY_PATH` pointing
at the same directory are still needed by hand.

`csrc/idris2curl_compat.h` holds `static inline` shims for the small
number of libcurl functions returning `const char *`
(`curl_easy_strerror` so far) -- both rc2's and upstream RefC's own
`%foreign` lowering hardcode `CFString` as non-const `char *`, which
collides with either backend's own `-Werror` (confirmed directly
against both, not inferred from one -- see `idris2-rc-cg/TODO.md`'s
"CFString's hardcoded `char *` return type" entry). Chez has no such
issue (dynamically typed, no C-level qualifier), and can't call the
`static inline` shim anyway -- it only exists in the header, never as
a real symbol in `libcurl.so`'s own table, so Chez's own dynamic load
would fail with "no entry for ...". Each such binding therefore
declares *three* `%foreign` targets: a plain
`"C:curl_easy_strerror,..."` entry Chez picks up, an
`"RefC:idris2curl_easy_strerror,..."` entry plain upstream `idris2
--cg refc` picks up (its own FFI tags are `["RefC", "C"]`), and an
`"RC2:idris2curl_easy_strerror,..."` entry `Compiler.RC2.Emit`'s own
`ffiTags` (`["RC2", "RefC", "C"]`, checked in that order) picks up
instead for rc2 specifically. Both static-linking backends also need
`-lcurl` reaching the linker -- rc2 derives it automatically from the
`%foreign` lib field (`Compiler.RC2.CC`'s own `compileCFile`), but
plain upstream RefC doesn't, so building with `--cg refc` still needs
`IDRIS2_LDLIBS`/`LDLIBS` set by hand. See `Network.Curl.Raw`'s own
`prim__curlEasyStrerror` for the pattern to follow for any future
`const char *`-returning binding.

## Conventions

- Code, comments, and commit messages: English.
- Never modify git config. Set identity inline per-commit only:
  `git -c user.name="..." -c user.email="..." commit ...`.
- Only commit when the user explicitly asks.
- ドキュメントを読めばわかる事はコードのコメントには書かず、参照リンクの記載に留める。
