#!/usr/bin/env bash
# Driver for the run-idris2-curl skill.
# Builds the idris2-curl library, installs it into a local package
# prefix, compiles the network-free UrlAndEscape.idr example against
# one or more backends, runs each, and checks the output.
#
# Usage: ./smoke.sh [--backend=chez|refc|rc2|all]
#   --backend=chez   (default) default Idris2 Chez backend only
#   --backend=refc   upstream idris2 --cg refc only
#   --backend=rc2    idris2-rc-cg's rc2 backend only (needs
#                    ../idris2-rc-cg checked out as a sibling dir,
#                    already built -- see that repo's own
#                    run-idris2-rc-cg skill)
#   --backend=all    all three, in order
#
# NOTE: this does NOT run examples/Get.idr or any other example that
# makes a real network request (those need outbound HTTP, which an
# agent sandbox may not allow) -- UrlAndEscape.idr only exercises
# curl_version/curl_easy_escape/unescape/curl_url_* locally.
set -euo pipefail

UNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$UNIT_DIR"

BACKEND=chez
for arg in "$@"; do
  case "$arg" in
    --backend=*) BACKEND="${arg#--backend=}" ;;
    *) echo "unknown arg: $arg" >&2; exit 1 ;;
  esac
done

PREFIX="$UNIT_DIR/.local-install"

echo "== type-checking package.ipkg (Chez) =="
nix-shell -p idris2 gcc gmp pkg-config curl --run 'idris2 --build package.ipkg'

echo "== installing library to local prefix =="
nix-shell -p idris2 gcc gmp pkg-config curl --run \
  "IDRIS2_PREFIX='$PREFIX' idris2 --install package.ipkg"

EXPECTED_PREFIX='curl_version: libcurl/'
LIBDIR_CMD='pkg-config --variable=libdir libcurl'

run_and_check() {
  local label="$1" bin="$2"
  echo "== running ($label) =="
  local out
  out="$(nix-shell -p gcc gmp curl pkg-config --run \
    "export LD_LIBRARY_PATH=\"\$($LIBDIR_CMD):\${LD_LIBRARY_PATH:-}\"; '$bin'")"
  echo "$out"
  case "$out" in
    "$EXPECTED_PREFIX"*) ;;
    *) echo "SMOKE TEST FAILED ($label): unexpected output" >&2; exit 1 ;;
  esac
  echo "$out" | grep -q '^escaped: a%20b%2Fc%3Fd$' || { echo "SMOKE TEST FAILED ($label): escape mismatch" >&2; exit 1; }
  echo "$out" | grep -q '^unescaped: a b/c?d$' || { echo "SMOKE TEST FAILED ($label): unescape mismatch" >&2; exit 1; }
}

build_chez() {
  echo "== compiling UrlAndEscape.idr (Chez) =="
  nix-shell -p idris2 gcc gmp pkg-config curl --run \
    "export IDRIS2_CFLAGS='-Icsrc'; IDRIS2_PREFIX='$PREFIX' idris2 -p curl -o smoke_urlget_chez examples/UrlAndEscape.idr"
  run_and_check chez "$UNIT_DIR/build/exec/smoke_urlget_chez"
}

build_refc() {
  echo "== compiling UrlAndEscape.idr (RefC) =="
  nix-shell -p idris2 gcc gmp pkg-config curl --run \
    "export IDRIS2_CFLAGS='-Icsrc'; export IDRIS2_LDLIBS=\"\$(pkg-config --libs libcurl)\"; IDRIS2_PREFIX='$PREFIX' idris2 --cg refc -p curl -o smoke_urlget_refc examples/UrlAndEscape.idr"
  run_and_check refc "$UNIT_DIR/build/exec/smoke_urlget_refc"
}

build_rc2() {
  local rc2_bin="$UNIT_DIR/../idris2-rc-cg/rc2/build/exec/idris2-rc2"
  if [ ! -x "$rc2_bin" ]; then
    echo "rc2 backend: $rc2_bin not found -- build idris2-rc-cg first (see its own run-idris2-rc-cg skill)" >&2
    exit 1
  fi
  echo "== compiling UrlAndEscape.idr (rc2) =="
  nix-shell -p gcc gmp pkg-config curl --run \
    "source '$UNIT_DIR/../idris2-rc-cg/env.sh'; export IDRIS2_PACKAGE_PATH=\"\$IDRIS2_PACKAGE_PATH:$PREFIX/idris2-0.8.0\"; export IDRIS2_CFLAGS='-Icsrc'; export IDRIS2_LDFLAGS=\"\$(pkg-config --libs-only-L libcurl)\"; '$rc2_bin' --cg rc2 -p curl -o smoke_urlget_rc2 examples/UrlAndEscape.idr"
  run_and_check rc2 "$UNIT_DIR/build/exec/smoke_urlget_rc2"
}

case "$BACKEND" in
  chez) build_chez ;;
  refc) build_refc ;;
  rc2) build_rc2 ;;
  all) build_chez; build_refc; build_rc2 ;;
  *) echo "unknown --backend=$BACKEND (want chez|refc|rc2|all)" >&2; exit 1 ;;
esac

echo "== smoke test OK =="
