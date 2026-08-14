#!/usr/bin/with-contenv bashio
INTERVAL="$(bashio::config 'refresh_seconds')"

# transparency: which interfaces the host actually has (host_network -> host netns)
IFACES="$(ip -o link show | awk -F': ' '{print $2}' | cut -d'@' -f1 | grep -v '^lo$' | tr '\n' ' ')"
bashio::log.info "static-arp: refresh=${INTERVAL}s | host interfaces: ${IFACES}"

# one-time validation: warn on duplicate IPs
seen=""
for i in $(bashio::config 'entries|keys'); do
  IP="$(bashio::config "entries[${i}].ip")"
  case " ${seen} " in
    *" ${IP} "*) bashio::log.warning "duplicate IP ${IP} in config — later entry wins" ;;
  esac
  seen="${seen} ${IP}"
done

# startup inventory: print the configured cameras sorted by IP (numeric,
# per-octet). The Configuration UI has no sortable columns, so this gives a
# readable, ordered overview in the Log.
INV=""
for i in $(bashio::config 'entries|keys'); do
  IP="$(bashio::config "entries[${i}].ip")"
  MAC="$(bashio::config "entries[${i}].mac")"
  if bashio::config.has_value "entries[${i}].name"; then
    NAME="$(bashio::config "entries[${i}].name")"
  else
    NAME="-"
  fi
  INV="${INV}${IP}|${NAME}|${MAC}"$'\n'
done
bashio::log.info "configured cameras (sorted by IP):"
printf '%s' "${INV}" | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | \
  while IFS='|' read -r IP NAME MAC; do
    [ -z "${IP}" ] && continue
    bashio::log.info "  $(printf '%-15s  %-24s  %s' "${IP}" "${NAME}" "${MAC}")"
  done

while true; do
  for i in $(bashio::config 'entries|keys'); do
    IP="$(bashio::config "entries[${i}].ip")"
    MAC="$(bashio::config "entries[${i}].mac")"
    if bashio::config.has_value "entries[${i}].name"; then
      LABEL="$(bashio::config "entries[${i}].name") (${IP})"
    else
      LABEL="${IP}"
    fi
    # runtime guard: skip malformed MAC (e.g. YAML edited outside the UI schema)
    if ! echo "${MAC}" | grep -Eiq '^([0-9a-f]{2}:){5}[0-9a-f]{2}$'; then
      bashio::log.warning "invalid MAC '${MAC}' for ${LABEL} — skipped"
      continue
    fi
    # auto-derive the egress interface for this destination. This is a route
    # lookup (not a neighbor lookup), so it returns dev even when the camera is
    # offline / ARP is INCOMPLETE. Robust to interface renames (e.g. USB NIC).
    IF="$(ip route get "${IP}" 2>/dev/null | grep -oE 'dev [^ ]+' | awk '{print $2}' | head -n1)"
    if [ -z "${IF}" ]; then
      bashio::log.warning "no route for ${LABEL} — cannot determine interface, skipped"
      continue
    fi
    if ip neigh replace "${IP}" lladdr "${MAC}" dev "${IF}" nud permanent; then
      bashio::log.info "pinned ${LABEL} -> ${MAC} on ${IF}"
    else
      bashio::log.warning "failed to pin ${LABEL} on ${IF}"
    fi
  done
  sleep "${INTERVAL}"
done
