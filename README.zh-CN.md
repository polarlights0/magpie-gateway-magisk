# magpie 网关 · Magisk 模块

把 [magpie](https://github.com/yetone/magpie) 的本地 AI 网关跑在手机上，开机自启、常驻后台，不用开着电脑或 App。

- 网关：`127.0.0.1:3425`
- 网页界面：`127.0.0.1:3430`

[English](README.md) · **简体中文**

## 不移植、不魔改

上游本来就提供 `android/arm64` 的构建（`make release-cli`，带 `-tags nogui`），并发布了 `magpie-cli-android-arm64` 和 `SHA256SUMS`。所以这里没有任何移植或改动，用的就是官方二进制。

上游没有的只有两件事，正是本模块补的：**开机自启**，以及下面这三个 Android/root 环境下的坑。

`magpie daemon install` 在 Android 上会直接返回 `ErrUnsupported`，官方让你用 Termux:Boot。

## 安装

1. 从 [Releases](../../releases) 下载 `magpie_gateway_v*.zip`
2. Magisk → 模块 → 从本地安装 → 选这个 zip → 重启手机

> **安装时需要联网**：zip 只有约 10 KB，不含 97 MB 的 magpie 二进制。安装脚本会从官方 release 下载并用 SHA256 校验，校验不过直接拒绝安装。实测 97.2 MB / 25 秒。
> 需要离线安装就用 `./build.sh --full` 打一个内置二进制的包（约 40 MB），Release 里也放了。

模块自带 `system/etc/resolv.conf`，所以要**重启**之后该文件才会出现。

安装完添加一个供应商：

```sh
M=/data/adb/modules/magpie_gateway
$M/mg provider add deepseek sk-…
$M/mg providers
```

命令行请用自带的 `mg` 包装脚本，**不要**直接调 `bin/magpie`，原因见下面「为什么不直接调二进制」。

## 「操作」按钮：直接打开网页界面

在 Magisk 里点本模块的**操作**按钮，会在浏览器里打开网页界面。如果服务是关着的，会先自动开启再打开，不用重启手机。

链接里带 `MAGPIE_WEB_KEY`，这个 key 只生成一次并保存在 `config/web.key`，所以每次点开的地址都一样。

## 开关：不用重启手机

```sh
M=/data/adb/modules/magpie_gateway

$M/ctl.sh off       # 立刻停掉
$M/ctl.sh on        # 立刻开启
$M/ctl.sh restart
$M/ctl.sh status    # 开关状态、网关进程号、网页端口
$M/ctl.sh url       # 打印网页界面链接
```

**Magisk 自带的模块开关，运行中也生效。** 在 Magisk 里把模块关掉只会写一个 `modules/magpie_gateway/disable` 文件，Magisk 本身要等下次开机才处理；而本模块的守护脚本每秒检查一次这个文件，所以点完大约 1 秒内网关就会停，不会"关了还在跑"。`ctl.sh status` 会说明是哪一种开关关的，`ctl.sh on` 也不会去覆盖 Magisk 的开关。

## 为什么不能直接调二进制

纯 Go 静态二进制在 Magisk 的 root 环境里既没有 `/etc/resolv.conf`，也没有 CA 证书路径。两个问题都在真机上复现过（Android 16 / arm64 / Magisk 31.1）：

| 问题 | 现象 | 本模块的处理 |
|---|---|---|
| 没有 `/etc/resolv.conf` | `lookup api.deepseek.com on [::1]:53: connection refused`，所有请求失效 | 模块自带 `system/etc/resolv.conf`；启动时把当前网络的 DNS 写入 `$CONF/resolv.conf`，在**私有挂载命名空间**里 bind 过去，不影响系统本身 |
| 没有 CA 证书 | `x509: certificate signed by unknown authority` | 每次启动从 `/system/etc/security/cacerts` 合成证书包，指给 `SSL_CERT_FILE` |

这套环境只存在于服务的挂载命名空间里，所以你在终端里直接跑 `bin/magpie` 会照样失败。`mg` 就是替你复现这套环境来执行命令的。

另外两个 Android 特有的坑（都已修）：

- 这台设备的 `ip route` **没有 `default` 条目**（路由在按网络的 policy 表里），所以就绪检测用 `ip route get`。
- `netstat -tln` 会把 `CLOSE_WAIT` 的对端连接也列出来，只看端口号会误判"网页还在监听"，所以只认 `LISTEN` 行。

## 目录结构

```
/data/adb/magpie/
├── config/magpie/         供应商、密钥、设置
├── config/web.key         网页界面 key（600）
├── config/addr            可选：网关地址覆盖
├── config/webaddr         可选：网页地址覆盖
├── cache/
├── logs/service.log       超过 2 MiB 自动轮转
├── disabled               存在即为 ctl.sh off 状态
├── resolv.conf            当前 DNS
└── cacerts.pem            CA 证书包
```

用户数据在模块目录之外，更新模块不会清掉。

## 端口

| | |
|---|---|
| 网关 | `127.0.0.1:3425` —— `echo 127.0.0.1:3426 > $CONF/config/addr` |
| 网页 | `127.0.0.1:3430` —— `echo 127.0.0.1:3431 > $CONF/config/webaddr` |

如果官方 App（`com.magpie.android`）正在运行，3425 会被它占着；magpie 会自己等待并在它退出后接手，同时本模块检测到 3430 被占用时会自动跳过网页界面，保证网关仍能起来。

## 自己构建

```sh
./build.sh          # 精简包（约 10 KB），安装时下载二进制
./build.sh --full   # 离线包（约 40 MB），内置二进制
```

版本和校验和只在 `module/settings.conf` 一处维护，`build.sh` 和 `customize.sh` 都读它。

## 注意

- magpie 会**自我更新**：有新版本时它会直接替换 `bin/magpie`（实测首次启动几分钟内就从 `0.1.4683` 变成 `0.1.4684`），所以打包时的 SHA256 在运行一段时间后对不上是正常的。想锁版本可以 `$M/mg update channel stable`。
- 卸载模块会停服务并保留 `/data/adb/magpie`；要彻底清掉就删这个目录。

## 许可证

本模块脚本为 MIT。magpie 本体为 MIT，版权归其作者；本仓库不重新分发其二进制，由构建或安装时从官方 release 获取并校验。
