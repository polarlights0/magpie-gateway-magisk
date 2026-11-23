# magpie gateway — Magisk module

Run [magpie](https://github.com/yetone/magpie)'s local AI gateway on an Android
phone as a boot-resident service, without opening the desktop or Android app.

`magpie serve` binds `127.0.0.1:3425`; the module also serves magpie's web UI on
`127.0.0.1:3430`.

There is **no port and no patched binary** here. Upstream already builds
`android/arm64` (`make release-cli`, `-tags nogui`) and publishes
`magpie-cli-android-arm64` with a `SHA256SUMS`. This module is the missing piece
upstream does not provide: boot integration and the Android/root runtime fixes
below. `magpie daemon install` returns `ErrUnsupported` on Android — it points at
Termux:Boot instead.

## Install

1. Download `magpie_gateway_v*.zip` from [Releases](../../releases).
2. Magisk → Modules → Install from storage → pick the zip → reboot.

The zip does **not** contain the 97 MB binary: `customize.sh` downloads the
pinned upstream release during install and verifies its SHA256 (measured: 97.2 MB
in 25 s). Installing therefore needs a working connection. For an offline flash,
build `./build.sh --full`, which embeds the binary.

The module ships `system/etc/resolv.conf`, so a reboot is required for that file
to appear.

Then add a provider:

```sh
M=/data/adb/modules/magpie_gateway
$M/mg provider add deepseek sk-…
$M/mg providers
```

Use the bundled `mg` wrapper, **not** `bin/magpie` directly — see *Why the
wrapper* below.

## The Magisk action button

Tapping **Action** on the module opens the web UI in your browser. If the service
is off, it is switched on first. The link carries `MAGPIE_WEB_KEY`, generated once
and kept in `config/web.key`, so the same URL works every time.

## On and off without rebooting

```sh
M=/data/adb/modules/magpie_gateway

$M/ctl.sh off       # stop supervisor + gateway now
$M/ctl.sh on        # start them now
$M/ctl.sh restart
$M/ctl.sh status
$M/ctl.sh url       # print the web UI link
```

Magisk's own module switch only writes `modules/magpie_gateway/disable`, which
upstream Magisk applies at the **next boot**. The supervisor polls for that file
every second, so toggling the module off in Magisk stops the gateway within about
a second instead of serving until reboot. `ctl.sh status` says which switch is
off, and `ctl.sh on` refuses to override Magisk's switch.

## Why the wrapper, and what the module fixes

A pure-Go static binary under Magisk has no `/etc/resolv.conf` and no CA path.
Both were reproduced on a real device (Android 16, arm64, Magisk 31.1):

| Problem | Symptom | Fix |
|---|---|---|
| No `/etc/resolv.conf` | `lookup api.deepseek.com on [::1]:53: connection refused` | module ships `system/etc/resolv.conf`; at start the live resolvers are written to `$CONF/resolv.conf` and bind-mounted inside a private mount namespace |
| No CA bundle | `x509: certificate signed by unknown authority` | bundle built at boot from `/system/etc/security/cacerts` into `SSL_CERT_FILE` |

Because that setup lives in the service's mount namespace, a plain
`bin/magpie` call from a terminal has neither and fails the same way. `mg`
reproduces the environment for CLI commands.

Two Android quirks that also bit, both fixed in the scripts:

- `ip route` has no `default` entry here (routes live in per-network policy
  tables), so the readiness probe uses `ip route get`.
- `netstat -tln` lists `CLOSE_WAIT` peers too, so a bare port grep reported the
  web UI as up after it had stopped. Port checks match `LISTEN` rows only.

## Layout

```
/data/adb/magpie/
├── config/magpie/         providers, keys, settings
├── config/web.key         the web UI key (600)
├── config/addr            optional gateway address override
├── config/webaddr         optional web UI address override
├── cache/
├── logs/service.log       rotated at 2 MiB
├── disabled               present while ctl.sh off
├── resolv.conf            live DNS servers
└── cacerts.pem            CA bundle
```

State is kept across module updates.

## Ports

| | |
|---|---|
| gateway | `127.0.0.1:3425` — `echo 127.0.0.1:3426 > $CONF/config/addr` |
| web UI | `127.0.0.1:3430` — `echo 127.0.0.1:3431 > $CONF/config/webaddr` |

If the magpie Android app (`com.magpie.android`) is running it owns 3425 already;
magpie logs that the second copy waits, and the module skips `--web` if 3430 is
taken so the gateway still comes up.

## Build

The release binary is ~97 MB, over GitHub's recommended file size, so it is not
committed and the published zip does not carry it. `customize.sh` downloads it
from the pinned upstream release at install time and refuses to install unless
the SHA256 matches. That keeps the flashable zip at ~10 KB.

```sh
./build.sh          # slim zip (~10 KB), downloads the binary at install
./build.sh --full   # offline zip (~40 MB) with the binary embedded
```

To bump the version, update `module/settings.conf` — `build.sh` and
`customize.sh` both read it from there.

Verified on-device: the install-time download pulled the 97.2 MB binary in 25 s
and the SHA256 matched the pinned value.

## CI

`.github/workflows/build.yml` builds the slim zip on every push and uploads it
as an artifact; pushing a `v*` tag publishes a Release with both the slim and
the full zip.

## Notes

- magpie updates itself in place: it replaces `bin/magpie` when a new release is
  out (observed `0.1.4683` → `0.1.4684` minutes after first start), so the
  packaged SHA256 stops matching. `$M/mg update channel stable` pins a channel.
- Removing the module stops the service and keeps `/data/adb/magpie`; delete that
  folder to purge.

## Licence

The module scripts are MIT. The bundled-at-build-time binary is magpie's, MIT,
© its authors; see [yetone/magpie](https://github.com/yetone/magpie).
