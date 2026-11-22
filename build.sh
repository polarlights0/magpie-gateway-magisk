#!/bin/sh
# build.sh — assemble the flashable Magisk zip.
#
# Runs on the host (Linux/macOS/CI), not on the phone, hence /bin/sh rather than
# Android's /system/bin/sh.
#
# The magpie release binary is ~97 MB, which is over GitHub's recommended file
# size, so it is not committed. This script fetches the exact pinned release
# from upstream, verifies it against the published SHA256SUMS, then packs the
# module with it.
#
#   ./build.sh            -> dist/magpie_gateway_v0.1.4683.zip
#   ./build.sh --no-fetch -> reuse a binary already in .cache/

set -eu

# --- pinned upstream release -------------------------------------------------
VERSION=v0.1.4683
BIN_NAME=magpie-cli-android-arm64
# from the release's SHA256SUMS (also checked against the file below)
BIN_SHA256=6de488018180c92b3b07ad4f1e7356cf93b4075fb72bc50d1329d875ab920fad
RELEASE_URL="https://github.com/yetone/magpie-releases/releases/download/$VERSION"

MODULE_ID=magpie_gateway
ROOT=$(cd "$(dirname "$0")" && pwd)
CACHE="$ROOT/.cache"
DIST="$ROOT/dist"

mkdir -p "$CACHE" "$DIST"

# --- 1. fetch and verify the upstream binary ---------------------------------
if [ "${1:-}" = "--no-fetch" ]; then
  echo "==> reusing $CACHE/$BIN_NAME"
  [ -f "$CACHE/$BIN_NAME" ] || { echo "missing $CACHE/$BIN_NAME" >&2; exit 1; }
else
  if [ ! -f "$CACHE/$BIN_NAME" ]; then
    echo "==> downloading $BIN_NAME ($VERSION)"
    curl -fSL --retry 3 -o "$CACHE/$BIN_NAME.part" "$RELEASE_URL/$BIN_NAME"
    mv -f "$CACHE/$BIN_NAME.part" "$CACHE/$BIN_NAME"
  else
    echo "==> cached $CACHE/$BIN_NAME"
  fi
fi

echo "==> verifying SHA256"
ACTUAL=$(sha256sum "$CACHE/$BIN_NAME" | cut -d' ' -f1)
if [ "$ACTUAL" != "$BIN_SHA256" ]; then
  echo "SHA256 mismatch" >&2
  echo "  expected $BIN_SHA256" >&2
  echo "  actual   $ACTUAL" >&2
  exit 1
fi
echo "    ok $ACTUAL"

# --- 2. stage the module tree ------------------------------------------------
STAGE="$DIST/stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/bin"

cp -a "$ROOT/module/." "$STAGE/"
cp "$CACHE/$BIN_NAME" "$STAGE/bin/magpie"

# permissions Magisk expects inside the zip
find "$STAGE" -type d -exec chmod 755 {} +
find "$STAGE" -type f -exec chmod 644 {} +
chmod 755 "$STAGE/service.sh" "$STAGE/action.sh" "$STAGE/ctl.sh" \
          "$STAGE/customize.sh" "$STAGE/uninstall.sh" "$STAGE/mg"
chmod 755 "$STAGE/bin/magpie"

# --- 3. pack -----------------------------------------------------------------
OUT="$DIST/${MODULE_ID}_${VERSION}.zip"
rm -f "$OUT"
( cd "$STAGE" && zip -r -q -X "$OUT" . )
rm -rf "$STAGE"

echo "==> $OUT"
ls -lh "$OUT"
sha256sum "$OUT"
