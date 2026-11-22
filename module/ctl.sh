#!/system/bin/sh
# ctl — switch magpie on and off without rebooting.
#
# Magisk's own module toggle only takes effect at the next boot, so this keeps a
# runtime switch instead:  `off` stops the supervisor and the gateway and drops
# a marker so a restart does not bring them back; `on` clears the marker and
# starts them again. Nothing here touches the module's enabled/disabled state.
#
#   ctl on | off | restart | start | stop | status | url

MODDIR=${0%/*}
case "$MODDIR" in
  /*) ;;
  *) MODDIR="$(cd "$MODDIR" 2>/dev/null && pwd)" ;;
esac
CONF=/data/adb/magpie
MARK=$CONF/disabled
PIDF=$CONF/run/magpie.pid
LOG=$CONF/logs/service.log

WEB_ADDR=127.0.0.1:3430
[ -f "$CONF/config/webaddr" ] && WEB_ADDR=$(head -1 "$CONF/config/webaddr")
ADDR=127.0.0.1:3425
[ -f "$CONF/config/addr" ] && ADDR=$(head -1 "$CONF/config/addr")

running() {
  [ -f "$PIDF" ] || return 1
  P=$(cat "$PIDF" 2>/dev/null)
  [ -n "$P" ] && kill -0 "$P" 2>/dev/null
}

stop_all() {
  # supervisor first: it would otherwise restart the child
  for p in $(pgrep -f "$MODDIR/service.sh" 2>/dev/null); do
    [ "$p" = "$$" ] && continue
    kill -TERM "$p" 2>/dev/null
  done
  sleep 1
  for p in $(pgrep -f "$MODDIR/service.sh" 2>/dev/null); do
    [ "$p" = "$$" ] && continue
    kill -KILL "$p" 2>/dev/null
  done
  if [ -f "$PIDF" ]; then
    P=$(cat "$PIDF" 2>/dev/null)
    [ -n "$P" ] && kill -TERM "$P" 2>/dev/null
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
  rm -f "$PIDF"
}

start_all() {
  [ -x "$MODDIR/service.sh" ] || { echo "service.sh missing"; return 1; }
  # detached: survive this shell exiting
  setsid /system/bin/sh "$MODDIR/service.sh" </dev/null >/dev/null 2>&1 &
  i=0
  while [ $i -lt 30 ]; do
    running && return 0
    i=$((i+1))
    sleep 1
  done
  return 1
}

case "$1" in
  on)
    rm -f "$MARK"
    # Magisk's own switch survives here; service.sh would exit at once, so say
    # so instead of appearing to start and silently stopping.
    if [ -f "$MODDIR/disable" ]; then
      echo "the module is switched off in Magisk — enable it there first"
      echo "(its own switch takes effect at the next boot; \`ctl.sh on\` alone cannot override it)"
      exit 1
    fi
    # already up?
    if running; then echo "already on"; exit 0; fi
    start_all && echo "on" || { echo "failed to start, see $LOG"; exit 1; }
    ;;
  off)
    mkdir -p "$CONF"
    echo "switched off $(date '+%F %T')" > "$MARK"
    stop_all
    echo "off"
    ;;
  start)
    start_all && echo "started" || { echo "failed to start, see $LOG"; exit 1; }
    ;;
  stop)
    stop_all
    echo "stopped (will start again at next boot)"
    ;;
  restart)
    rm -f "$MARK"
    stop_all
    start_all && echo "restarted" || { echo "failed to start, see $LOG"; exit 1; }
    ;;
  status)
    if [ -f "$MODDIR/disable" ]; then
      echo "switch:  off (Magisk's own switch)"
    elif [ -f "$MARK" ]; then
      echo "switch:  off (ctl.sh off)"
    else
      echo "switch:  on"
    fi
    if running; then
      echo "gateway: running (pid $(cat "$PIDF")) on $ADDR"
    else
      echo "gateway: stopped"
    fi
    if netstat -tln 2>/dev/null | grep LISTEN | grep -q ":${WEB_ADDR#*:} "; then
      echo "web:     listening on $WEB_ADDR"
    else
      echo "web:     not listening"
    fi
    ;;
  url)
    K=$(cat "$CONF/config/web.key" 2>/dev/null)
    [ -n "$K" ] && echo "http://$WEB_ADDR/?k=$K" || echo "no key yet — start it once"
    ;;
  *)
    echo "usage: ctl on|off|start|stop|restart|status|url"
    exit 1
    ;;
esac
