#!/bin/sh
# Registers the data servers and the namespace of the gateway with the
# coordinators. It skips what exists, so that it can run again.
set -eu

admin() {
  # The first coordinator that answers
  for c in coordinator-0 coordinator-1 coordinator-2; do
    if oxia admin --admin-address "$c:6651" "$@"; then
      return 0
    fi
  done
  return 1
}

for i in 0 1 2; do
  until admin dataserver get "dataserver-$i" >/dev/null 2>&1 ||
        admin dataserver create "dataserver-$i" \
          --public "dataserver-$i:6648" --internal "dataserver-$i:6649"; do
    sleep 2
  done
done

until admin namespace get kubernetes >/dev/null 2>&1 ||
      admin namespace create kubernetes --initial-shards 3 --replication-factor 3; do
  sleep 2
done
echo "Oxia is ready"
