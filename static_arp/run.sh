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

# normalize stored config to IP order. Add-ons have no "on save" hook, but HA
# restarts a running add-on when its config is saved, so this runs right after a
# Save. If the stored entries are not already sorted by IP, rewrite them via the
# Supervisor API (POST /addons/self/options) so the Configuration panel shows
# them ordered. Idempotent: on the next start they are already sorted -> no-op.
SORT_JQ='sort_by(.ip | split(".") | map(tonumber))'
if [ -f /data/options.json ] && command -v jq >/dev/null 2>&1; then
  CUR="$(jq -c '.entries' /data/options.json 2>/dev/null)"
  NEW="$(jq -c ".entries | ${SORT_JQ}" /data/options.json 2>/dev/null)"
  if [ -n "${NEW}" ] && [ "${CUR}" != "${NEW}" ]; then
    PAYLOAD="$(jq -c "{options: {refresh_seconds: .refresh_seconds, entries: (.entries | ${SORT_JQ})}}" /data/options.json)"
    if curl -fsS -X POST \
         -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
         -H "Content-Type: application/json" \
         -d "${PAYLOAD}" \
         http://supervisor/addons/self/options >/dev/null 2>&1; then
      bashio::log.info "stored config normalized to IP order"
    else
      bashio::log.warning "could not persist IP-sorted config (log view is still sorted)"
    fi
  fi
fi

# startup inventory: print the configured cameras sorted by IP. The
# Configuration UI has no sortable columns, so this gives a readable, ordered
# overview in the Log. We prefix each line with a zero-padded numeric IP key
# and plain-sort on it, so ordering does not depend on busybox `sort -n`
# handling a mixed last field.
INV=""
for i in $(bashio::config 'entries|keys'); do
  IP="$(bashio::config "entries[${i}].ip")"
  MAC="$(bashio::config "entries[${i}].mac")"
  if bashio::config.has_value "entries[${i}].name"; then
    NAME="$(bashio::config "entries[${i}].name")"
  else
    NAME="-"
  fi
  IFS=. read -r o1 o2 o3 o4 <<EOF
${IP}
EOF
  KEY="$(printf '%03d%03d%03d%03d' "${o1:-0}" "${o2:-0}" "${o3:-0}" "${o4:-0}")"
  INV="${INV}${KEY}|${IP}|${NAME}|${MAC}"$'\n'
done
bashio::log.info "configured cameras (sorted by IP):"
bashio::log.info "  $(printf '%-15s  %-17s  %s' 'IP' 'MAC' 'NAME')"
printf '%s' "${INV}" | sort | \
  while IFS='|' read -r KEY IP NAME MAC; do
    [ -z "${IP}" ] && continue
    bashio::log.info "  $(printf '%-15s  %-17s  %s' "${IP}" "${MAC}" "${NAME}")"
  done

while true; do
  for i in $(bashio::config 'entries|keys'); do
    IP="$(bashio::config "entries[${i}].ip")"
    MAC="$(bashio::config "entries[${i}].mac")"
    # pad the IP to a fixed width so the "->" always lines up (last octet gets
    # 2/1/0 trailing spaces for a 1/2/3-digit octet)
    IPP="$(printf '%-15s' "${IP}")"
    # optional description, shown after the MAC as "(name)"
    if bashio::config.has_value "entries[${i}].name"; then
      DESC=" ($(bashio::config "entries[${i}].name"))"
    else
      DESC=""
    fi
    # runtime guard: skip malformed MAC (e.g. YAML edited outside the UI schema)
    if ! echo "${MAC}" | grep -Eiq '^([0-9a-f]{2}:){5}[0-9a-f]{2}$'; then
      bashio::log.warning "${IPP} -> invalid MAC '${MAC}'${DESC} — skipped"
      continue
    fi
    # auto-derive the egress interface for this destination. This is a route
    # lookup (not a neighbor lookup), so it returns dev even when the camera is
    # offline / ARP is INCOMPLETE. Robust to interface renames (e.g. USB NIC).
    IF="$(ip route get "${IP}" 2>/dev/null | grep -oE 'dev [^ ]+' | awk '{print $2}' | head -n1)"
    if [ -z "${IF}" ]; then
      bashio::log.warning "${IPP} -> ${MAC}${DESC} — no route, cannot determine interface, skipped"
      continue
    fi
    if ip neigh replace "${IP}" lladdr "${MAC}" dev "${IF}" nud permanent; then
      bashio::log.info "pinned ${IPP} -> ${MAC}${DESC} on ${IF}"
    else
      bashio::log.warning "failed to pin ${IPP} -> ${MAC}${DESC} on ${IF}"
    fi
  done
  sleep "${INTERVAL}"
done
