#!/usr/bin/env bash
set -euo pipefail
PORT="${1:-}"
[[ -n "$PORT" ]] || { echo "Usage: $0 <ssh-port>"; exit 1; }

# On the host: pick the first IPv4 from `hostname -I`
HOST_IPV4="$(ip -f inet address show scope global | grep -Po 'inet \K[\d.]+' | tail -n 1)"
[ -n "$HOST_IPV4" ] || { echo "Could not parse host IPv4"; exit 1; }


# 1) Remote setup of the VM — pass HOST_IPV4 as $1 to the remote shell
ssh -o UserKnownHostsFile=/dev/null \
    -o StrictHostKeyChecking=no \
    -p "$PORT" root@127.0.0.1 /bin/sh -s "$HOST_IPV4" <<'EOSSH'
set -eux
service vwifi-client stop

LAST_OCT=$(cat /sys/class/net/eth0/address | cut -d: -f6)

uci set vwifi.config.server_ip="$1"
uci set vwifi.config.mac_prefix="02:00:00:00:00:${LAST_OCT}"
uci set vwifi.config.enabled='1'
uci commit vwifi

echo "Restarting wireless"
service vwifi-client start
echo "Restarting"
wifi config
lime-config
wifi down
sleep 7
wifi up
EOSSH

