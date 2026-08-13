#!/usr/bin/with-contenv bashio
IF="$(bashio::config 'interface')"
INTERVAL="$(bashio::config 'refresh_seconds')"
bashio::log.info "static-arp: interface=${IF} refresh=${INTERVAL}s"

# one-time validation: warn on duplicate IPs
seen=""
for i in $(bashio::config 'entries|keys'); do
  IP="$(bashio::config "entries[${i}].ip")"
  case " ${seen} " in
    *" ${IP} "*) bashio::log.warning "duplicate IP ${IP} in config — later entry wins" ;;
  esac
  seen="${seen} ${IP}"
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
    if ip neigh replace "${IP}" lladdr "${MAC}" dev "${IF}" nud permanent; then
      bashio::log.info "pinned ${LABEL} -> ${MAC} on ${IF}"
    else
      bashio::log.warning "failed to pin ${LABEL} on ${IF}"
    fi
  done
  sleep "${INTERVAL}"
done
