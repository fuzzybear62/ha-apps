#!/usr/bin/with-contenv bashio
IF="$(bashio::config 'interface')"
INTERVAL="$(bashio::config 'refresh_seconds')"
bashio::log.info "static-arp: interface=${IF} refresh=${INTERVAL}s"
while true; do
  for i in $(bashio::config 'entries|keys'); do
    IP="$(bashio::config "entries[${i}].ip")"
    MAC="$(bashio::config "entries[${i}].mac")"
    if ip neigh replace "${IP}" lladdr "${MAC}" dev "${IF}" nud permanent; then
      bashio::log.info "pinned ${IP} -> ${MAC} on ${IF}"
    else
      bashio::log.warning "failed to pin ${IP} on ${IF}"
    fi
  done
  sleep "${INTERVAL}"
done
