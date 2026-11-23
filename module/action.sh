#!/system/bin/sh
# Magisk 操作按钮 —— 在浏览器里打开 magpie 的网页界面。
#
# 在 Magisk 里点这个模块的「操作」按钮就会执行本脚本。它会先确认网关在跑
# （被关掉的话直接启动，不需要重启手机），然后把带 key 的链接交给浏览器。

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

# --- 确认服务在运行 ---
if [ ! -f "$CONF/run/magpie.pid" ] || ! kill -0 "$(cat "$CONF/run/magpie.pid" 2>/dev/null)" 2>/dev/null; then
  if [ -f "$CONF/disabled" ]; then
    say "magpie 处于关闭状态，正在开启…"
    "$CTL" on >/dev/null 2>&1
  else
    say "正在启动 magpie…"
    "$CTL" start >/dev/null 2>&1
  fi

  # 等网页端口就绪
  i=0
  while [ $i -lt 30 ]; do
    if netstat -tln 2>/dev/null | grep LISTEN | grep -q ":${WEB_ADDR#*:} "; then break; fi
    i=$((i+1))
    sleep 1
  done
fi

if [ -z "$KEY" ]; then
  say "！缺少网页 key —— 请执行："
  say "  su -c '$CTL restart'"
  say "  （key 在第一次启动时生成）"
  exit 1
fi

URL="http://$WEB_ADDR/?k=$KEY"

if ! netstat -tln 2>/dev/null | grep LISTEN | grep -q ":${WEB_ADDR#*:} "; then
  say "！$WEB_ADDR 上没有任何服务在监听"
  say "  日志：$CONF/logs/service.log"
  exit 1
fi

say "正在打开：$URL"
am start -a android.intent.action.VIEW -d "$URL" >/dev/null 2>&1 \
  || am start --user 0 -a android.intent.action.VIEW -d "$URL" >/dev/null 2>&1

say "网关地址：http://127.0.0.1:3425/v1"
say "日志目录：$CONF/logs/service.log"
