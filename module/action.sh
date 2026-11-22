#!/system/bin/sh
# Magisk action button — opens magpie's web UI.
#
# Magisk runs this when you tap "Action" on the module. It makes sure the
# gateway is up (starting it if you switched it off, no reboot needed) and then
# hands the signed link to the browser.

MODDIR=${0%/*}
case "$MODDIR" in
  /*) ;;
  *) MODDIR="$(cd "$MODDIR" 2>/dev/null && pwd)" ;;
esac
CONF=/data/adb/magpie
CTL="$MODDIR/ctl.sh"

say() { echo "$*"; }

WEB_ADDR=127.0.0.1:3430
[ -f "$CONF/config/webaddr" ] && WEB_ADDR=$(head -1 "$CONF/config/webaddr")

KEY=$(cat "$CONF/config/web.key" 2>/dev/null)

# --- make sure the service is running ---
if [ ! -f "$CONF/run/magpie.pid" ] || ! kill -0 "$(cat "$CONF/run/magpie.pid" 2>/dev/null)" 2>/dev/null; then
  if [ -f "$CONF/disabled" ]; then
    say "magpie is switched off — switching it on…"
    "$CTL" on >/dev/null 2>&1
  else
    say "starting magpie…"
    "$CTL" start >/dev/null 2>&1
  fi

  # wait for the web port to answer
  i=0
  while [ $i -lt 30 ]; do
    if netstat -tln 2>/dev/null | grep LISTEN | grep -q ":${WEB_ADDR#*:} "; then break; fi
    i=$((i+1))
    sleep 1
  done
fi

if [ -z "$KEY" ]; then
  say "! web key missing — run: su -c '$CTL restart'"
  say "  (the key is made on first start)"
  exit 1
fi

URL="http://$WEB_ADDR/?k=$KEY"

if ! netstat -tln 2>/dev/null | grep LISTEN | grep -q ":${WEB_ADDR#*:} "; then
  say "! nothing is listening on $WEB_ADDR"
  say "  log: $CONF/logs/service.log"
  exit 1
fi

say "opening $URL"
am start -a android.intent.action.VIEW -d "$URL" >/dev/null 2>&1 \
  || am start --user 0 -a android.intent.action.VIEW -d "$URL" >/dev/null 2>&1

say "gateway: http://127.0.0.1:3425/v1"
say "logs:    $CONF/logs/service.log"
