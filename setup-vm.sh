#!/usr/bin/env bash
# push_vwifi_client.sh : select the port of the VM and push vwifi-client, then tweak mac80211_hwsim

set -euo pipefail
PORT="${1:-}"
[[ -n "$PORT" ]] || { echo "Usage: $0 <ssh-port>"; exit 1; }

# On the host: pick the first IPv4 from `hostname -I`
HOST_IPV4="$(hostname -I | awk '{for(i=1;i<=NF;i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/){print $i; exit}}')"
[ -n "$HOST_IPV4" ] || { echo "Could not parse host IPv4 from hostname -I"; exit 1; }

# 1) Copy vwifi-client to the VM
scp -o UserKnownHostsFile=/dev/null \
    -o StrictHostKeyChecking=no \
    -P "$PORT" -O \
    libremesh-virtual-mesh/vwifi/vwifi-client root@127.0.0.1:/usr/bin/vwifi-client

# 2) Remote setup of the VM — pass HOST_IPV4 as $1 to the remote shell
ssh -o UserKnownHostsFile=/dev/null \
    -o StrictHostKeyChecking=no \
    -p "$PORT" root@127.0.0.1 /bin/sh -s "$HOST_IPV4" <<'EOSSH'
set -eux
HOST_IPV4="${1:?missing host IPv4}"

# Make sure it's executable (scp should keep it executable)
chmod 0755 /usr/bin/vwifi-client || true

# Unload mac80211_hwsim if present (underscore for module name)
if lsmod | grep -q '^mac80211_hwsim'; then
  rmmod mac80211_hwsim
fi

# 0 radios when loading the module persistant across (re)boots: OpenWrt's kmodloader reads /etc/modules.d at boot
printf '%s\n' 'mac80211_hwsim radios=0' > /etc/modules.d/mac80211-hwsim

# Load now with the parameter (runtime effect)
modprobe mac80211_hwsim radios=0 || insmod mac80211_hwsim radios=0

# fix the maccaddr of the wlan0-mesh
# last octet of eth0/br-lan MAC -> 02:00:00:00:00:XX
LAST_OCT=$(cat /sys/class/net/eth0/address | cut -d: -f6)
uci set wireless.lm_wlan0_mesh_radio0.macaddr="02:00:00:00:00:${LAST_OCT}"
uci commit wireless

# --- procd service for vwifi-client using the HOST's IPv4 ---
cat >/etc/init.d/vwifi-client <<'EOF'
#!/bin/sh /etc/rc.common
START=99
STOP=10
USE_PROCD=1
PROG=/usr/bin/vwifi-client

start_service() {
    [ -x "$PROG" ] || return 1
    procd_open_instance
    # Command: vwifi-client <HOST_IPV4> --number 2
    procd_set_param command "$PROG" "__HOST_IP__" --number 2
    procd_set_param respawn 5 10 0
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance

    # Instance 2: helper that waits for a PHY then brings Wi-Fi up
    procd_open_instance
    procd_set_param nice 10
    procd_set_param command /bin/sh -c '
        for i in $(seq 1 120); do
            if ls /sys/class/ieee80211/* >/dev/null 2>&1; then
                wifi up || wifi reload || true
                exit 0
            fi
            sleep 1
        done
        echo "vwifi-client: no PHY detected after 120s; skipping wifi up" >&2
        exit 0
    '
    procd_close_instance
}
EOF

# Inject the actual host IPv4 safely
sed -i "s/__HOST_IP__/${HOST_IPV4}/g" /etc/init.d/vwifi-client
chmod +x /etc/init.d/vwifi-client
/etc/init.d/vwifi-client enable

reboot
EOSSH

