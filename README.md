# Fuzzybear apps — Home Assistant add-on repository

A small repository of custom Home Assistant add-ons (called **Apps** since
Home Assistant 2026.2). Add the repository URL to your Home Assistant instance
and install from the store.

**Add this repository:** Settings → **Apps** → **App Store** → ⋮ (top right) →
**Repositories** → paste:

```
https://github.com/fuzzybear62/ha-apps
```

## Add-ons in this repository

| Add-on | Description |
|--------|-------------|
| **Static ARP for cameras** | Pins camera `IP → MAC` as permanent entries in the host ARP table, to keep IP cameras reachable from Home Assistant across flaky/cascaded Wi‑Fi repeaters. |

---

# Static ARP for cameras

## Why this exists

IP cameras reached over **cascaded Wi‑Fi repeaters** can intermittently become
unreachable *from Home Assistant* while still working perfectly from the
vendor's own app. The stream backend (go2rtc) fails with:

```
mse: streams: dial tcp 192.168.x.y:554: connect: no route to host
```

`no route to host` is `EHOSTUNREACH` — the host's ARP resolution for the camera
failed (the neighbor entry goes `INCOMPLETE`). The distinctive symptoms:

- **The vendor app keeps working** during the fault — it reaches the camera via
  the cloud/P2P relay (unicast, camera-originated), which does **not** depend on
  local LAN broadcast.
- **It fails even with a viewer open**, i.e. even while RTP is flowing — so it is
  **not** an idle/aging timeout.
- **Only rebooting the camera recovers it** — a reboot forces re‑association and
  a gratuitous ARP that re‑seeds the bridge/forwarding tables along the repeater
  chain.

The coherent root cause is **broadcast (ARP) black‑holing across cheap cascaded
repeaters**: established unicast survives, but anything that needs a *fresh ARP
resolution* (a broadcast) is dropped. Once an established session drops (a brief
roam/flap), Home Assistant must re‑resolve the camera's MAC via ARP broadcast →
black‑holed → stuck until the camera itself emits a gratuitous ARP (reboot).

This add-on removes Home Assistant's dependence on that broadcast: it installs a
**permanent static neighbor entry** so the host always knows the camera's MAC
and never needs to ARP‑resolve it.

> This is a workaround for a Layer‑2 delivery problem in the repeater chain, not
> a fix for Home Assistant or go2rtc. The robust structural fix is a wired/mesh
> backhaul; this add-on is the practical, software‑only mitigation when that is
> not an option.

## What it does

For each configured camera it runs, in the host network namespace:

```
ip neigh replace <ip> lladdr <mac> dev <iface> nud permanent
```

`nud permanent` means the kernel never ages or re‑validates the entry, so Home
Assistant never falls back to a (black‑holed) ARP broadcast for that camera.

## How it works

- **`host_network: true`** — the add-on shares the **host network namespace**,
  so it writes the *same* neighbor table that go2rtc (running inside the
  `homeassistant` container, also host‑networked) uses. What the add-on pins is
  what go2rtc sees.
- **`privileged: [NET_ADMIN]`** — the capability required to modify the kernel
  neighbor table.
- **Auto‑derived interface** — the egress interface is resolved per camera with
  `ip route get <ip>`. This is a *route* lookup, not a *neighbor* lookup, so it
  returns the correct `dev` **even when the camera is offline / ARP is
  INCOMPLETE**. There is no interface to configure, and it is robust to NIC
  renames (e.g. a USB Ethernet adapter whose predictable name changes across OS
  updates).
- **Re‑arm loop** — entries are (re)written every `refresh_seconds`, so they
  also survive a link flap on the interface.
- **Validation** — `ip`/`mac` are format‑checked by the options schema (the UI
  rejects a malformed value on save); a malformed MAC that reaches the container
  anyway is skipped with a log warning. Duplicate IPs are reported at startup.

## Requirements & compatibility

- **Home Assistant OS** (the add-on / Supervisor stack). This add-on relies on
  `host_network` + `NET_ADMIN`, i.e. the Supervisor add-on model.
- **Architecture: `aarch64`** — built for 64‑bit ARM. Developed and validated on
  **Home Assistant OS on a Raspberry Pi 5**; it applies equally to other aarch64
  HAOS hosts (e.g. RPi 4). To target another architecture, add it to `arch` and
  `build.yaml`.
- The camera and the Home Assistant host must be on the **same IPv4 subnet**
  (an on‑link destination), which is the case this workaround addresses.

## Installation

1. **Add the repository** (see the top of this file): Settings → Apps → App
   Store → ⋮ → Repositories → paste the URL → Add.
2. ⋮ → **Check for updates**. Under **Fuzzybear apps** you will see
   **Static ARP for cameras**.
3. Open it → **Install** (the Supervisor builds the image from the Dockerfile).
4. Open the **Configuration** tab and add your cameras (see below).
5. **Start** the add-on, then enable **Start on boot** and **Watchdog**.
6. Open the **Log** tab and confirm lines like
   `pinned esternacitofonocam (192.168.188.51) -> 48:22:54:c3:46:80 on enu1`.

## Configuration

```yaml
refresh_seconds: 60
entries:
  - name: esternacitofonocam   # optional, only used in the log
    ip: 192.168.188.51
    mac: "48:22:54:c3:46:80"
  - name: giardino
    ip: 192.168.188.163
    mac: "f0:09:0d:7d:6b:2d"
```

| Option | Type | Description |
|--------|------|-------------|
| `refresh_seconds` | int (10–3600) | How often entries are re‑written (flap resilience). |
| `entries[].name` | string, optional | Label shown in the add-on log for readability. |
| `entries[].ip` | IPv4 | Camera IP (validated). |
| `entries[].mac` | MAC `aa:bb:cc:dd:ee:ff` | Camera MAC (validated, colon format). |

## Finding a camera's MAC

From the **Advanced SSH & Web Terminal** add-on, while the camera is reachable:

```bash
ping -c1 <camera-ip> && ip neigh show <camera-ip>
```

or read it from your router's client list, or the camera app
(*Device info → MAC*).

## Verifying

From the SSH terminal:

```bash
ip neigh show | grep -i PERMANENT
```

Each camera should appear as `PERMANENT`, e.g.:

```
192.168.188.51 lladdr 48:22:54:c3:46:80 PERMANENT
```

## Troubleshooting

- **`Operation not permitted` on `ip neigh`** (AppArmor): add `apparmor: false`
  to `static_arp/config.yaml`, bump the version, and update the add-on.
- **`no route for … — cannot determine interface`**: the camera IP is not on any
  connected subnet of the host. Check the IP and that the host is on that LAN.
- **Camera still drops with the entry `PERMANENT`**: the black‑hole is
  bidirectional (the camera cannot ARP‑resolve Home Assistant either). No
  HA‑side ARP change can cure that — the fix moves to the repeater/network
  (broadcast handling) or a wired/mesh backhaul.

## Updating

Bump `version` in `static_arp/config.yaml`, push, then in Home Assistant:
⋮ → **Check for updates** → the add-on offers the new version.

## License

[MIT](LICENSE) — the license commonly used by Home Assistant community add-ons.
