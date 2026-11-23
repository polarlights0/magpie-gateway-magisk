#!/system/bin/sh
# ctl —— 不重启手机，直接开关 magpie。
#
# Magisk 自带的模块开关只写一个 disable 文件、下次开机才生效，所以这里另做
# 一个运行时开关：off 停掉守护脚本和网关并留一个标记，重启也不会被拉起；
# on 清掉标记并重新启动。这里不改动模块本身的启用/禁用状态。
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
  # 先杀守护脚本，否则它会把网关重新拉起来
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
  [ -x "$MODDIR/service.sh" ] || { echo "缺少 service.sh，模块可能没装好"; return 1; }
  # 用 setsid 脱离当前终端，这样本脚本退出后它继续跑
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
    # Magisk 自己的开关还关着的话，service.sh 启动后会立刻退出，
    # 与其假装成功，不如直接说明
    if [ -f "$MODDIR/disable" ]; then
      echo "模块在 Magisk 里是关闭状态 —— 请先在 Magisk 中启用它"
      echo "（Magisk 的开关下次开机才生效，单靠 ctl.sh on 无法覆盖）"
      exit 1
    fi
    if running; then echo "本来就在运行，无需重复启动"; exit 0; fi
    start_all && echo "已开启" || { echo "启动失败，请查看日志：$LOG"; exit 1; }
    ;;
  off)
    mkdir -p "$CONF"
    echo "关闭于 $(date '+%F %T')" > "$MARK"
    stop_all
    echo "已关闭"
    ;;
  start)
    start_all && echo "已启动" || { echo "启动失败，请查看日志：$LOG"; exit 1; }
    ;;
  stop)
    stop_all
    echo "已停止（下次开机会自动启动）"
    ;;
  restart)
    rm -f "$MARK"
    stop_all
    start_all && echo "已重启" || { echo "启动失败，请查看日志：$LOG"; exit 1; }
    ;;
  status)
    if [ -f "$MODDIR/disable" ]; then
      echo "开关:   关闭（Magisk 自带开关）"
    elif [ -f "$MARK" ]; then
      echo "开关:   关闭（ctl.sh off）"
    else
      echo "开关:   开启"
    fi
    if running; then
      echo "网关:   运行中（pid $(cat "$PIDF")），地址 $ADDR"
    else
      echo "网关:   未运行"
    fi
    if netstat -tln 2>/dev/null | grep LISTEN | grep -q ":${WEB_ADDR#*:} "; then
      echo "网页:   正在监听 $WEB_ADDR"
    else
      echo "网页:   未监听"
    fi
    ;;
  url)
    K=$(cat "$CONF/config/web.key" 2>/dev/null)
    [ -n "$K" ] && echo "http://$WEB_ADDR/?k=$K" || echo "还没有生成 key —— 先启动一次"
    ;;
  *)
    echo "用法: ctl on|off|start|stop|restart|status|url"
    exit 1
    ;;
esac
