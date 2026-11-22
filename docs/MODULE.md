# magpie gateway on Android

Runs the **official** `magpie-cli-android-arm64` release as a boot-resident
gateway (`magpie serve --web`) on `127.0.0.1:3425`, with its web UI on
`127.0.0.1:3430`, so agents and the panel work without the Android app open.

Upstream already ships an Android target (`make release-cli` builds
`android/arm64` with `-tags nogui`), so nothing is patched or recompiled here:
`bin/magpie` is the unmodified release binary (SHA256
`6de488018180c92b3b07ad4f1e7356cf93b4075fb72bc50d1329d875ab920fad`).

`magpie daemon install` is unavailable on Android — upstream returns
`ErrUnsupported` and points at Termux:Boot. This module is that missing boot
integration.

## The Magisk action button

Tapping **Action** on this module in Magisk opens the web UI in your browser.
If the service is switched off it is started first, so the button always lands
on a working page. The link carries `MAGPIE_WEB_KEY`, which is generated once
and kept in `config/web.key`, so the same URL works every time.

## On and off without rebooting

Magisk's own module toggle only takes effect at the next boot. `ctl.sh` is a
runtime switch instead:

```sh
M=/data/adb/modules/magpie_gateway

$M/ctl.sh off       # stop the supervisor and the gateway now
$M/ctl.sh on        # start them again now
$M/ctl.sh restart   # after changing a provider or the port
$M/ctl.sh status    # switch state, gateway pid, web port
$M/ctl.sh url       # print the web UI link
```

`off` drops a marker at `/data/adb/magpie/disabled`; `service.sh` exits early
while it exists, so a crash-restart cannot bring the gateway back behind your
back. The marker is cleared by `on` and by `restart`. Reinstalling the module
also clears it.

**Magisk's own switch is honoured while running.** Toggling the module off in
Magisk writes `modules/magpie_gateway/disable`, and the supervisor polls for it
every second, so the gateway stops within about a second instead of serving
until the next reboot. `ctl.sh status` reports which switch is off, and
`ctl.sh on` refuses to override Magisk's switch (turn it back on in Magisk;
`enable` there is also only applied at the next boot).

## Commands

Use the bundled `mg` wrapper, **not** `bin/magpie` directly — a plain call has
neither the resolver namespace nor the CA bundle, so every request fails with
`[::1]:53: connection refused`.

```sh
$M/mg provider add deepseek sk-…     # add a provider
$M/mg providers
$M/mg provider test deepseek         # 401 = reachable, key rejected
$M/mg models
$M/mg quota
```

## What the module fixes

A pure-Go static binary under Magisk has no `/etc/resolv.conf` and no CA path.
Both were reproduced on this device and are handled here:

| Problem | Symptom | Fix |
|---|---|---|
| No `/etc/resolv.conf` | `lookup api.deepseek.com on [::1]:53: connection refused` | module ships `system/etc/resolv.conf`; at start the live resolvers are written to `$CONF/resolv.conf` and bind-mounted inside a private mount namespace |
| No CA bundle | `x509: certificate signed by unknown authority` | bundle built at boot from `/system/etc/security/cacerts` into `SSL_CERT_FILE` |

Two Android quirks that also bit:

- `ip route` has no `default` entry here (routes live in per-network policy
  tables), so the readiness probe uses `ip route get`.
- `netstat -tln` lists `CLOSE_WAIT` peers too, so a bare port grep reports the
  web UI as up after it stopped. Port checks match `LISTEN` rows only.

## magpie updates itself in place

`bin/magpie` is the upstream release binary, but magpie checks for updates and
replaces its own executable — observed going `0.1.4683` → `0.1.4684` inside the
module dir within minutes of first start, which also invalidates the SHA256
above. That is upstream behaviour, not something the module does. To keep the
packaged version, stop the gateway (`ctl.sh off`) and replace `bin/magpie`
again; to stay on a channel, `$M/mg update channel stable`.

## Layout

```
/data/adb/magpie/
├── config/magpie/         providers, keys, settings
├── config/web.key         the web UI key (600)
├── cache/
├── logs/service.log       rotated at 2 MiB
├── disabled               present while switched off
├── resolv.conf            live DNS servers
└── cacerts.pem            CA bundle
```

## Ports

| | |
|---|---|
| gateway | `127.0.0.1:3425` (`MAGPIE_ADDR`, override in `config/addr`) |
| web UI | `127.0.0.1:3430` (override in `config/webaddr`) |

If the magpie Android app (`com.magpie.android`) is running it already owns
3425; the module then logs that the second copy waits, and `--web` is skipped if
3430 is taken so the gateway still comes up.

## Uninstall

Removing the module stops the supervisor and the gateway and keeps
`/data/adb/magpie` (providers and keys); delete that folder to purge. The module
ships `system/etc/resolv.conf`, which goes away with it.
