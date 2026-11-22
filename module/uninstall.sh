#!/system/bin/sh
# Stop the gateway before the module is removed.
#
# Order matters: the supervisor (service.sh) restarts its child every 5s, so
# killing only the child achieves nothing. Kill the supervisor first, then the
# child. Patterns are matched narrowly on purpose — a broad `pkill -f` on the
# state dir would also match this script's own command line.

MODDIR=${0%/*}
case "$MODDIR" in
  /*) ;;
  *) MODDIR="$(cd "$MODDIR" 2>/dev/null && pwd)" ;;
esac
CONF=/data/adb/magpie
PIDF=$CONF/run/magpie.pid

# 1. supervisor loop, matched by the absolute path of service.sh
SUP=$(pgrep -f "sh $MODDIR/service.sh" 2>/dev/null)
[ -z "$SUP" ] && SUP=$(pgrep -f "$MODDIR/service.sh" 2>/dev/null)
for p in $SUP; do
  [ "$p" = "$$" ] && continue
  kill -TERM "$p" 2>/dev/null
done

sleep 2
for p in $SUP; do
  kill -KILL "$p" 2>/dev/null
done

# 2. the gateway itself, by recorded pid and by exact command
if [ -f "$PIDF" ]; then
  PID=$(cat "$PIDF" 2>/dev/null)
  [ -n "$PID" ] && kill -TERM "$PID" 2>/dev/null
fi
for p in $(pgrep -f "$MODDIR/bin/magpie serve" 2>/dev/null); do
  [ "$p" = "$$" ] && continue
  kill -TERM "$p" 2>/dev/null
done
sleep 1
for p in $(pgrep -f "$MODDIR/bin/magpie serve" 2>/dev/null); do
  [ "$p" = "$$" ] && continue
  kill -KILL "$p" 2>/dev/null
done

# User state (providers, keys) is kept on purpose. To purge as well, drop the
# leading '#' on the next line.
# rm -rf "$CONF"
