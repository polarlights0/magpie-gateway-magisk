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

BIN="$MODPATH/bin/magpie"
[ -f "$BIN" ] || abort "! bin/magpie missing from the package"
grep -q "magpie" "$BIN" 2>/dev/null || abort "! bin/magpie does not look like the magpie binary"

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/bin/magpie" 0 0 0755
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
