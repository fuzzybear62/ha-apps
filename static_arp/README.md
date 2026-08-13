# Static ARP for cameras

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
interface: enu1
refresh_seconds: 60
entries:
  - name: esternacitofonocam   # optional, only used in the log
    ip: 192.168.188.51
    mac: "48:22:54:c3:46:80"
```

- `interface` — host LAN interface (find with `ip route get <camera-ip>`).
- `entries` — one entry per camera:
  - `name` *(optional)* — label shown in the add-on log for readability.
  - `ip` / `mac` — the pair pinned as a permanent neighbor entry.

Duplicate `ip` values are reported in the log at startup
(`duplicate IP … — later entry wins`); the last entry for that IP is applied.
