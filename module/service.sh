#!/system/bin/sh
# magpie gateway — boot-resident local AI gateway + web UI
#
# Runs the official magpie-cli-android-arm64 binary as `magpie serve --web`.
# Two Android-specific gaps are fixed here, both reproduced on-device:
#   1. Go's static binary has no /etc/resolv.conf to read, so every lookup dies
#      on [::1]:53. The service gets its own resolver file in a private mount
#      namespace; the system's view is untouched.
#   2. It has no CA path, so TLS fails with x509 "unknown authority". We point
#      SSL_CERT_FILE at a bundle built from the live system store each boot.

MODDIR=${0%/*}
# always absolute: a relative path breaks once the cwd is gone (module update,
# module dir replaced) and the supervisor restarts the child.
case "$MODDIR" in
  /*) ;;
  *) MODDIR="$(cd "$MODDIR" 2>/dev/null && pwd)" ;;
esac
CONF=/data/adb/magpie
BIN=$MODDIR/bin/magpie
LOG=$CONF/logs/service.log
PIDF=$CONF/run/magpie.pid
MARK=$CONF/disabled
# Magisk's own toggle: it only writes this file and applies it at the next
# boot, so the running service has to watch it itself or it keeps serving.
MDISABLE=$MODDIR/disable

mkdir -p "$CONF/run" "$CONF/logs" "$CONF/config" "$CONF/cache"
chmod 700 "$CONF" 2>/dev/null

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

if [ -f "$LOG" ]; then
  sz=$(wc -c < "$LOG" 2>/dev/null || echo 0)
  if [ "$sz" -gt 2097152 ]; then mv -f "$LOG" "$LOG.1"; fi
fi

log "=== 服务启动 ==="

# toggled off from the action button / ctl.sh, or by Magisk's own switch
# (which by itself only takes effect at the next boot): stay down.
if [ -f "$MARK" ] || [ -f "$MDISABLE" ]; then
  log "已被关闭（存在 $MARK 或 $MDISABLE），退出"
  exit 0
fi

if [ ! -x "$BIN" ]; then
  log "严重错误：$BIN 不存在或不可执行"
  exit 1
fi

# ---- wait for a usable route ----
# Android's main table has no "default" entry (routes live in per-network
# policy tables), so probe with `ip route get` instead of grepping for one.
i=0
while [ $i -lt 60 ]; do
  if ip route get 223.5.5.5 >/dev/null 2>&1; then break; fi
  i=$((i+1))
  sleep 2
done
if [ $i -ge 60 ]; then log "警告：120 秒内没有可用路由"; fi

# ---- live resolvers from the active networks ----
DNS_LIST=$(dumpsys connectivity 2>/dev/null \
  | tr ',' '\n' \
  | sed -n 's/^\/\([0-9][0-9.]*\)$/\1/p' \
  | grep -v '^127\.' | awk '!seen[$0]++' | head -3)

{
  for d in $DNS_LIST; do echo "nameserver $d"; done
  echo "nameserver 223.5.5.5"
  echo "nameserver 8.8.8.8"
} > "$CONF/resolv.conf"
log "DNS 配置 -> $(tr '\n' ' ' < "$CONF/resolv.conf")"

# ---- CA bundle from the live system store ----
cat /system/etc/security/cacerts/*.0 > "$CONF/cacerts.pem" 2>/dev/null
CAC=$(grep -c 'BEGIN CERTIFICATE' "$CONF/cacerts.pem" 2>/dev/null || echo 0)
log "CA 证书包：$CAC 张"
if [ "$CAC" -lt 1 ]; then log "警告：CA 证书包为空，TLS 会失败"; fi

# ---- gateway address (override: echo 127.0.0.1:3426 > $CONF/config/addr) ----
ADDR=127.0.0.1:3425
[ -f "$CONF/config/addr" ] && ADDR=$(head -1 "$CONF/config/addr")

# ---- web UI address and its key ----
# The key is made once and kept, so the link the action button opens stays the
# same across restarts. magpie wants 16+ of [A-Za-z0-9._~-].
WEB_ADDR=127.0.0.1:3430
[ -f "$CONF/config/webaddr" ] && WEB_ADDR=$(head -1 "$CONF/config/webaddr")

KEYF=$CONF/config/web.key
if [ ! -s "$KEYF" ]; then
  tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 32 > "$KEYF"
  chmod 600 "$KEYF"
fi
WEB_KEY=$(cat "$KEYF" 2>/dev/null)

export HOME="$CONF"
export XDG_CONFIG_HOME="$CONF/config"
export XDG_CACHE_HOME="$CONF/cache"
export SSL_CERT_FILE="$CONF/cacerts.pem"
export MAGPIE_ADDR="$ADDR"
export MAGPIE_WEB_KEY="$WEB_KEY"
export PATH="/system/bin:/system/xbin:$PATH"

# ---- supervise ----
# A plain `wait "$CHILD"` blocks until the gateway exits on its own, so a
# disable flag written while it runs would go unnoticed until the next boot.
# Poll instead: 1s while it runs, and take the child down when either the
# runtime switch or Magisk's own toggle appears.
off_now() { [ -f "$MARK" ] || [ -f "$MDISABLE" ]; }

while true; do
  if off_now; then log "运行中被关闭，退出"; exit 0; fi

  # the app's own copy, or another instance, may hold the web port; serving the
  # gateway alone still works, so fall back instead of crash-looping
  WEBBIND="--web=$WEB_ADDR"
  # `netstat -tln` also lists CLOSE_WAIT peers here, so a bare port grep gives
  # false positives; only a LISTEN row on the local port counts.
  if netstat -tln 2>/dev/null | grep LISTEN | grep -q ":${WEB_ADDR#*:} "; then
    log "警告：$WEB_ADDR 已被占用，只提供网关、不提供网页界面"
    WEBBIND=""
  fi

  log "正在启动：serve $ADDR ${WEBBIND:-（不带网页）}"

  unshare -m /system/bin/sh -c '
    SRC="$1"; BIN="$2"; shift 2
    if [ -e /system/etc/resolv.conf ]; then
      mount --bind "$SRC" /system/etc/resolv.conf 2>/dev/null && exec "$BIN" serve "$@"
    fi
    HOSTS=$(cat /system/etc/hosts 2>/dev/null)
    mount -t tmpfs tmpfs /system/etc || exit 97
    cp "$SRC" /system/etc/resolv.conf
    [ -n "$HOSTS" ] && printf "%s\n" "$HOSTS" > /system/etc/hosts
    exec "$BIN" serve "$@"
  ' _ "$CONF/resolv.conf" "$BIN" $WEBBIND >> "$LOG" 2>&1 &

  CHILD=$!
  echo "$CHILD" > "$PIDF"
  log "进程号 $CHILD"

  # poll while the child lives; stop it as soon as the switch flips
  while kill -0 "$CHILD" 2>/dev/null; do
    if off_now; then
      log "运行中被关闭，正在停止进程 $CHILD"
      kill -TERM "$CHILD" 2>/dev/null
      sleep 2
      kill -KILL "$CHILD" 2>/dev/null
      wait "$CHILD" 2>/dev/null
      rm -f "$PIDF"
      log "已停止"
      exit 0
    fi
    sleep 1
  done

  wait "$CHILD" 2>/dev/null
  RC=$?
  log "网关退出，返回码 rc=$RC"

  if off_now; then log "已关闭，不再重启"; exit 0; fi

  if [ "$RC" = "97" ]; then
    log "DNS 命名空间准备失败，60 秒后重试"
    sleep 60
  fi
  sleep 5
done
