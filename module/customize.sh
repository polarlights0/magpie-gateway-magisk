#!/system/bin/sh
SKIPUNZIP=0

CONF=/data/adb/magpie
ARCH=$(getprop ro.product.cpu.abi)

ui_print "- magpie gateway installer"
ui_print "- arch: $ARCH"

case "$ARCH" in
  arm64-v8a) ;;
  *)
    ui_print "! only arm64-v8a is supported (this device: $ARCH)"
    abort "! unsupported architecture"
    ;;
esac

# pinned upstream release
. "$MODPATH/settings.conf"

BIN="$MODPATH/bin/magpie"

# --- fetch the release binary if the zip did not carry it --------------------
# The binary is ~97 MB, so the published zip ships without it and it is pulled
# from the official release here, then checked against the pinned SHA256.
if [ ! -s "$BIN" ]; then
  URL="https://github.com/yetone/magpie-releases/releases/download/$MAGPIE_VERSION/$MAGPIE_BIN_NAME"
  mkdir -p "$MODPATH/bin"

  ui_print "- downloading magpie $MAGPIE_VERSION (arm64, ~97 MB)"
  ui_print "  $URL"

  BB=$(command -v busybox 2>/dev/null)
  [ -n "$BB" ] || BB=/data/adb/magisk/busybox

  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 -o "$BIN" "$URL" || true
  elif [ -x "$BB" ]; then
    "$BB" wget -O "$BIN" "$URL" || true
  fi

  if [ ! -s "$BIN" ]; then
    ui_print "! download failed (no network, or the release moved)"
    ui_print "  Offline install: fetch that file yourself and rebuild the zip with"
    ui_print "  ./build.sh, or drop the binary at"
    ui_print "  /data/adb/modules/magpie_gateway/bin/magpie after installing."
    abort "! magpie binary missing"
  fi
else
  ui_print "- using the bundled magpie binary"
fi

# --- verify what we are about to run ---------------------------------------
GOT=$("$BB" sha256sum "$BIN" 2>/dev/null | cut -d' ' -f1)
[ -n "$GOT" ] || GOT=$(sha256sum "$BIN" 2>/dev/null | cut -d' ' -f1)

if [ "$GOT" != "$MAGPIE_BIN_SHA256" ]; then
  ui_print "! SHA256 mismatch — refusing to install"
  ui_print "  expected $MAGPIE_BIN_SHA256"
  ui_print "  got      $GOT"
  rm -f "$BIN"
  abort "! bad binary"
fi
ui_print "- binary verified ($MAGPIE_VERSION)"

chmod 755 "$BIN"

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$BIN" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/ctl.sh" 0 0 0755
set_perm "$MODPATH/mg" 0 0 0755

# Persistent state lives outside the module dir so updates never wipe it.
mkdir -p "$CONF/run" "$CONF/logs" "$CONF/config" "$CONF/cache"
chmod 700 "$CONF"

# a fresh install starts switched on even if an old marker survived
rm -f "$CONF/disabled"

ui_print "- state dir: $CONF"
ui_print "- gateway:   http://127.0.0.1:3425/v1"
ui_print "- web UI:    Magisk > this module > Action button"
ui_print "- on/off:    $MODPATH/ctl.sh on|off   (no reboot)"
ui_print "- logs:      $CONF/logs/service.log"
ui_print "- CLI:       $MODPATH/mg provider add <preset> <key>"
ui_print "- reboot to start"
