# Static ARP table

Pins camera `IP -> MAC` entries as **permanent** in the Home Assistant host ARP
table. Runs host-networked with `NET_ADMIN` and re-arms every `refresh_seconds`,
so entries survive interface flaps.

## Why

Cameras behind cascaded WiFi repeaters can drop off the host's ARP resolution
(broadcast/ARP black-holing across the repeater chain), producing
`dial tcp <ip>:554: connect: no route to host` in go2rtc even though the camera
is up. A permanent neighbor entry bypasses HA-side ARP resolution entirely.

## Configuration

```yaml
refresh_seconds: 60
entries:
  - ip: 192.168.188.51
    mac: "48:22:54:c3:46:80"
    name: esternacitofonocam   # optional, only used in the log
```

Fields are shown in the Configuration panel in **IP → MAC → NAME** order
(schema-key order). After you **Save**, the add-on rewrites the stored `entries`
**sorted by IP**: there is no add-on "on save" hook, but HA restarts the add-on
on save, and on start it normalizes the config to IP order via the Supervisor
API (`POST /addons/self/options`). So the next time you open the panel the
entries are listed by ascending IP. The startup log prints the same
IP·MAC·NAME table, always sorted by IP.

The egress interface is **auto-derived per entry** with `ip route get <ip>`
(a route lookup, so it works even when the camera is offline / ARP is
INCOMPLETE). No interface needs to be configured — this is robust to interface
renames, e.g. a USB Ethernet adapter whose name changes across OS updates.
The interfaces present on the host are logged at startup.

- `entries` — one entry per camera:
  - `name` *(optional)* — label shown in the add-on log for readability.
  - `ip` / `mac` — the pair pinned as a permanent neighbor entry.

`ip` and `mac` are format-validated by the add-on options schema, so the UI
rejects a malformed value on save (MAC must be `aa:bb:cc:dd:ee:ff`, IPv4 dotted
quad). As a second guard, a malformed MAC that reaches the container anyway
(e.g. YAML edited outside the UI) is skipped with a log warning.

Duplicate `ip` values are reported in the log at startup
(`duplicate IP … — later entry wins`); the last entry for that IP is applied.
