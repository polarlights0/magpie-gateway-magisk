#!/system/bin/sh
SKIPUNZIP=0

CONF=/data/adb/magpie
ARCH=$(getprop ro.product.cpu.abi)

ui_print "- magpie 网关 安装程序"
ui_print "- 架构: $ARCH"

case "$ARCH" in
  arm64-v8a) ;;
  *)
    ui_print "！本模块只支持 arm64-v8a（当前设备: $ARCH）"
    abort "！架构不支持"
    ;;
esac

# 固定使用的上游版本
. "$MODPATH/settings.conf"

BIN="$MODPATH/bin/magpie"

# --- 包内没有二进制时，安装时下载 -------------------------------------------
# 二进制约 97 MB，所以发布的 zip 不带它，而是安装时从官方 release 拉取，
# 然后再用固定的 SHA256 校验。
if [ ! -s "$BIN" ]; then
  URL="https://github.com/yetone/magpie-releases/releases/download/$MAGPIE_VERSION/$MAGPIE_BIN_NAME"
  mkdir -p "$MODPATH/bin"

  ui_print "- 正在下载 magpie $MAGPIE_VERSION（arm64，约 97 MB）"
  ui_print "  $URL"
  ui_print "  请保持网络连接，大约需要 30 秒…"

  BB=$(command -v busybox 2>/dev/null)
  [ -n "$BB" ] || BB=/data/adb/magisk/busybox

  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 -o "$BIN" "$URL" || true
  elif [ -x "$BB" ]; then
    "$BB" wget -O "$BIN" "$URL" || true
  fi

  if [ ! -s "$BIN" ]; then
    ui_print "！下载失败（没有网络，或该版本已被上游移除）"
    ui_print "  离线安装办法：自己下载上面那个文件，再用 ./build.sh --full"
    ui_print "  重新打包，或安装后手动放到"
    ui_print "  /data/adb/modules/magpie_gateway/bin/magpie"
    abort "！缺少 magpie 二进制"
  fi
else
  ui_print "- 使用包内自带的 magpie 二进制"
fi

# --- 校验即将运行的二进制 ---------------------------------------------------
GOT=$("$BB" sha256sum "$BIN" 2>/dev/null | cut -d' ' -f1)
[ -n "$GOT" ] || GOT=$(sha256sum "$BIN" 2>/dev/null | cut -d' ' -f1)

if [ "$GOT" != "$MAGPIE_BIN_SHA256" ]; then
  ui_print "！SHA256 校验不通过，拒绝安装"
  ui_print "  期望 $MAGPIE_BIN_SHA256"
  ui_print "  实际 $GOT"
  rm -f "$BIN"
  abort "！二进制校验失败"
fi
ui_print "- 二进制校验通过（$MAGPIE_VERSION）"

chmod 755 "$BIN"

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$BIN" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/ctl.sh" 0 0 0755
set_perm "$MODPATH/mg" 0 0 0755

# 用户数据放在模块目录之外，更新模块不会把它清掉
mkdir -p "$CONF/run" "$CONF/logs" "$CONF/config" "$CONF/cache"
chmod 700 "$CONF"

# 全新安装一律从「开启」状态开始，清掉可能残留的关闭标记
rm -f "$CONF/disabled"

ui_print "- 数据目录: $CONF"
ui_print "- 网关地址: http://127.0.0.1:3425/v1"
ui_print "- 网页界面: Magisk 中本模块的「操作」按钮"
ui_print "- 开关命令: $MODPATH/ctl.sh on|off（无需重启）"
ui_print "- 日志位置: $CONF/logs/service.log"
ui_print "- 命令行:   $MODPATH/mg provider add <供应商> <密钥>"
ui_print "- 安装完成，重启手机后生效"
