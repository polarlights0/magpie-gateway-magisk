#!/bin/sh
# build.sh — assemble the flashable Magisk zip.
#
# Two flavours:
#   slim (default)  no binary; customize.sh downloads the pinned release and
#                   verifies its SHA256 at install time. ~20 KB, which is what
#                   gets published as a Release asset.
#   --full          embeds the ~97 MB binary, for offline flashing. ~40 MB.
#
#   ./build.sh              -> dist/magpie_gateway_v0.1.4683.zip       (slim)
#   ./build.sh --full       -> dist/magpie_gateway_v0.1.4683-full.zip  (offline)
#   ./build.sh --no-fetch   reuse a binary already in .cache/

set -eu

ROOT=$(cd "$(dirname "$0")" && pwd)
MODULE_ID=magpie_gateway
CACHE="$ROOT/.cache"
DIST="$ROOT/dist"

MODE=slim
NO_FETCH=0
for a in "$@"; do
  case "$a" in
    --full)     MODE=full ;;
    --slim)     MODE=slim ;;
    --no-fetch) NO_FETCH=1 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

# pinned upstream release (shared with customize.sh)
. "$ROOT/module/settings.conf"

mkdir -p "$CACHE" "$DIST"

# --- 1. fetch and verify the upstream binary (full mode only) ---------------
if [ "$MODE" = full ]; then
  SRC="$CACHE/$MAGPIE_BIN_NAME"

  if [ "$NO_FETCH" = 1 ]; then
    [ -f "$SRC" ] || { echo "missing $SRC" >&2; exit 1; }
    echo "==> reusing $SRC"
  elif [ ! -f "$SRC" ]; then
    echo "==> downloading $MAGPIE_BIN_NAME ($MAGPIE_VERSION)"
    curl -fSL --retry 3 -o "$SRC.part" \
      "https://github.com/yetone/magpie-releases/releases/download/$MAGPIE_VERSION/$MAGPIE_BIN_NAME"
    mv -f "$SRC.part" "$SRC"
  else
    echo "==> cached $SRC"
  fi

  echo "==> verifying SHA256"
  ACTUAL=$(sha256sum "$SRC" | cut -d' ' -f1)
  if [ "$ACTUAL" != "$MAGPIE_BIN_SHA256" ]; then
    echo "SHA256 mismatch" >&2
    echo "  expected $MAGPIE_BIN_SHA256" >&2
    echo "  actual   $ACTUAL" >&2
    exit 1
  fi
  echo "    ok $ACTUAL"
fi

# --- 2. stage the module tree ----------------------------------------------
STAGE="$DIST/stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"

cp -a "$ROOT/module/." "$STAGE/"

if [ "$MODE" = full ]; then
  mkdir -p "$STAGE/bin"
  cp "$CACHE/$MAGPIE_BIN_NAME" "$STAGE/bin/magpie"
  chmod 755 "$STAGE/bin/magpie"
fi

find "$STAGE" -type d -exec chmod 755 {} +
find "$STAGE" -type f -exec chmod 644 {} +
chmod 755 "$STAGE/service.sh" "$STAGE/action.sh" "$STAGE/ctl.sh" \
          "$STAGE/customize.sh" "$STAGE/uninstall.sh" "$STAGE/mg"
[ -f "$STAGE/bin/magpie" ] && chmod 755 "$STAGE/bin/magpie"

# --- 3. pack ---------------------------------------------------------------
SUFFIX=""
[ "$MODE" = full ] && SUFFIX="-full"
OUT="$DIST/${MODULE_ID}_${MAGPIE_VERSION}${SUFFIX}.zip"
rm -f "$OUT"
( cd "$STAGE" && zip -r -q -X "$OUT" . )
rm -rf "$STAGE"

echo "==> $OUT ($MODE)"
ls -lh "$OUT"
sha256sum "$OUT"
