# Changelog

All notable changes to the **Static ARP for cameras** add-on are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

## 2.1.1

### Changed
- Startup inventory is now an aligned **`IP · MAC · NAME`** table with a header
  row — column order mirrors the add-on's purpose (the IP we reach, the MAC we
  pin, then the label).

### Fixed
- Inventory now sorts **reliably by IP**. The previous `sort -t. … -k4,4n`
  mis-ordered on busybox because the last field mixed the octet with `name|mac`;
  entries are now prefixed with a zero-padded numeric IP key and plain-sorted.

## 2.1.0

### Added
- Startup inventory in the log: the configured cameras are printed **sorted by
  IP** as an aligned table. The Configuration UI has no sortable columns, so
  this gives a readable, ordered overview without changing how entries are
  stored.

## 2.0.0

### Changed
- **Breaking:** removed the `interface` option. The egress interface is now
  **auto-derived per camera** with `ip route get <ip>` — a route lookup, so it
  resolves the correct `dev` even when the camera is offline / ARP is
  `INCOMPLETE`. This is robust to interface renames (e.g. a USB Ethernet adapter
  whose predictable name changes across OS updates).
- The interfaces present on the host are now logged at startup for transparency.

### Upgrade note
If the Supervisor reports an invalid option after updating, open **Configuration**
and delete the leftover `interface:` line, then restart the add-on. Camera
entries are preserved.

## 1.2.0

### Added
- Schema-level format validation for `ip` (IPv4) and `mac`
  (`aa:bb:cc:dd:ee:ff`): the UI now rejects a malformed value on save.
- Runtime guard that skips a malformed MAC (e.g. YAML edited outside the UI)
  with a log warning instead of failing silently.

## 1.1.0

### Added
- Optional per-entry `name`, shown in the log for readability
  (`pinned <name> (<ip>) -> <mac> on <iface>`).
- Duplicate-IP detection: repeated IPs are reported at startup
  (`duplicate IP … — later entry wins`).

## 1.0.0

### Added
- Initial release. Pins camera `IP → MAC` as **permanent** neighbor entries in
  the host ARP table to work around ARP/broadcast black-holing across cascaded
  Wi-Fi repeaters (`no route to host` in go2rtc).
- Host-networked (`host_network: true`) with `NET_ADMIN`, so entries land in the
  same neighbor table go2rtc uses.
- Configurable `entries` list and `refresh_seconds` re-arm loop (flap
  resilience).
- Add-on icon and logo.
