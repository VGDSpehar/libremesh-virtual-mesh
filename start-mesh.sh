#!/usr/bin/env bash
set -euo pipefail

# ========= Config =========
SESSION="libremesh_mesh"         # tmux session name (when starting outside tmux)
WINDOW="VM_network"                # tmux window name (created inside current session if already in tmux)

BASE_IMAGE_GZ="bin/targets/x86/64/openwrt-x86-64-generic-ext4-combined.img.gz"
LIBREMESH_DIR="libremesh-virtual-mesh/images"
RAW_IMAGE="$LIBREMESH_DIR/base.img"
VM1_IMAGE="$LIBREMESH_DIR/vm1-overlay.qcow2"
VM2_IMAGE="$LIBREMESH_DIR/vm2-overlay.qcow2"
VM3_IMAGE="$LIBREMESH_DIR/vm3-overlay.qcow2"
VM_TEST="$LIBREMESH_DIR/vm-test-overlay.qcow2"

# Host IP
HOST_IP=$(hostname -I | cut -d ' ' -f1)
[ -n "$HOST_IP" ] || { echo "Couldn't determine the HOST_IP"; exit 1; }

VWIFI_CMD="vwifi-server -u"   # pane 0
VM1_SSH_PORT=2201             # pane 2
VM2_SSH_PORT=2202             # pane 3
VM3_SSH_PORT=2203             # pane 3

# QEMU common
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
QEMU_IMG="${QEMU_IMG:-qemu-img}"
QEMU_COMMON=(-enable-kvm -M q35 -cpu host -smp 2 -m 512M -nographic)

# SSH options (this prevents fingerprints errors when rerunning multiple times)
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=2)

# If you re-build the base image, set RECREATE_OVERLAYS=1 to force fresh overlays
RECREATE_OVERLAYS="${RECREATE_OVERLAYS:-0}"

# ========= Helpers =========
require() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found."; exit 1; }; }

prepare_images() {
  require gzip
  require "$QEMU_IMG"
  
  # Ensure the directory that will hold VM images exists
  mkdir -p "$LIBREMESH_DIR"

  if [[ ! -f "$BASE_IMAGE_GZ" ]]; then
    echo "ERROR: $BASE_IMAGE_GZ not found. Build OpenWrt first."
    exit 1
  fi

  # (Re)decompress raw base image if missing or older than gz
  if [[ ! -f "$RAW_IMAGE" || "$BASE_IMAGE_GZ" -nt "$RAW_IMAGE" ]]; then
    echo "[+] Decompressing base image -> $RAW_IMAGE"
    set +e
    gzip -dc "$BASE_IMAGE_GZ" > "$RAW_IMAGE".tmp
    status=$?
    set -e
    if [[ $status -ne 0 && $status -ne 2 ]]; then
	echo "ERROR: gzip failed (exit $status)" >&2
        rm -f "$RAW_IMAGE".tmp
        exit $status
    fi
    mv "$RAW_IMAGE".tmp "$RAW_IMAGE"
    # Force overlay recreation if base changed
    RECREATE_OVERLAYS=1
  fi

  local RAW_ABS
  RAW_ABS="$(realpath "$RAW_IMAGE")"

  # Create/recreate overlays
  if [[ "$RECREATE_OVERLAYS" == "1" && -f "$VM1_IMAGE" ]]; then rm -f "$VM1_IMAGE"; fi
  if [[ "$RECREATE_OVERLAYS" == "1" && -f "$VM2_IMAGE" ]]; then rm -f "$VM2_IMAGE"; fi
  if [[ "$RECREATE_OVERLAYS" == "1" && -f "$VM3_IMAGE" ]]; then rm -f "$VM3_IMAGE"; fi
  if [[ "$RECREATE_OVERLAYS" == "1" && -f "$VM_TEST" ]]; then rm -f "$VM_TEST"; fi

  if [[ ! -f "$VM1_IMAGE" ]]; then
    echo "[+] Creating overlay $VM1_IMAGE"
    "$QEMU_IMG" create -f qcow2 -F raw -b "$RAW_ABS" "$VM1_IMAGE" >/dev/null
  fi
  if [[ ! -f "$VM2_IMAGE" ]]; then
    echo "[+] Creating overlay $VM2_IMAGE"
    "$QEMU_IMG" create -f qcow2 -F raw -b "$RAW_ABS" "$VM2_IMAGE" >/dev/null
  fi
  if [[ ! -f "$VM3_IMAGE" ]]; then
    echo "[+] Creating overlay $VM3_IMAGE"
    "$QEMU_IMG" create -f qcow2 -F raw -b "$RAW_ABS" "$VM3_IMAGE" >/dev/null
  fi
  if [[ ! -f "$VM_TEST" ]]; then
    echo "[+] Creating overlay $VM_TEST"
    "$QEMU_IMG" create -f qcow2 -F raw -b "$RAW_ABS" "$VM_TEST" >/dev/null
  fi
}

start_tmux_env() {
  require tmux
  if [[ -n "${TMUX:-}" ]]; then
      # We are already inside tmux, so create a brand‑new window
      CUR_SESSION="$(tmux display-message -p '#S')"
  
      # -a  → automatically pick the lowest unused window index
      # -P  → print the new window's target
      # -F  → choose what is printed; we want "session:window_index"
      TARGET="$(tmux new-window -a -P -F '#{session_name}:#{window_index}' \
                                -n "$WINDOW" -c "$PWD" -t "$CUR_SESSION")"
  else
      # ---------- unchanged outside‑tmux path ----------
      tmux has-session -t "$SESSION" 2>/dev/null && tmux kill-session -t "$SESSION"
      tmux new-session -d -s "$SESSION" -n "$WINDOW"
      TARGET="$SESSION:0"
  fi
}

pane() { echo "$TARGET.$1"; }

send() {
  local pane_id="$1"; shift
  tmux send-keys -t "$pane_id" "$@" C-m
}

launch() {
  require "$QEMU_BIN"

  # Pane 0: vwifi-server (or warn)
  send "$(pane 0)" "command -v ${VWIFI_CMD%% *} >/dev/null && $VWIFI_CMD || echo 'vwifi-server not found; skipping'"

  # Create other panes and layout
  tmux split-window  -h   -t "$TARGET"                      # pane 1 (right)
  tmux select-pane   -t "$(pane 1)"
  tmux split-window  -v   -t "$TARGET"                      # pane 3 (below 1)
  tmux select-pane   -t "$(pane 0)"
  tmux split-window  -v   -t "$TARGET"                      # pane 2 (below 0)
  tmux select-pane   -t "$(pane 3)"
  tmux split-window  -h   -t "$TARGET"                      # pane 4 (right of 3)
  tmux select-layout -t "$TARGET" tiled

  # Pane 1: VM1 (LibreMesh style; two NICs; SSH fwd on 2201)
  # NOTE: we changed hostfwd to '-:22' so it doesn't rely on a fixed guest IP.
  send "$(pane 1)" "
$QEMU_BIN \
  ${QEMU_COMMON[*]} \
  -drive file=$VM1_IMAGE,if=virtio,format=qcow2 \
  -device virtio-net-pci,mac=52:54:00:00:00:01,netdev=mesh0 \
  -netdev user,id=mesh0,net=10.13.0.0/16,hostfwd=tcp::$VM1_SSH_PORT-10.13.00.01:22 \
  -device virtio-net-pci,netdev=wan0 \
  -netdev user,id=wan0
"

  # Pane 2: VM2 (same base; single NIC; SSH fwd on 2202)
  send "$(pane 2)" "
$QEMU_BIN \
  ${QEMU_COMMON[*]} \
  -drive file=$VM2_IMAGE,if=virtio,format=qcow2 \
  -device virtio-net-pci,mac=52:54:00:00:00:02,netdev=mesh0 \
  -netdev user,id=mesh0,net=10.13.0.0/16,hostfwd=tcp::$VM2_SSH_PORT-10.13.00.02:22 \
  -device virtio-net-pci,netdev=wan0 \
  -netdev user,id=wan0
"
# Pane 3: VM2 (same base; single NIC; SSH fwd on 2203)
  send "$(pane 3)" "
$QEMU_BIN \
  ${QEMU_COMMON[*]} \
  -drive file=$VM3_IMAGE,if=virtio,format=qcow2 \
  -device virtio-net-pci,mac=52:54:00:00:00:03,netdev=mesh0 \
  -netdev user,id=mesh0,net=10.13.0.0/16,hostfwd=tcp::$VM3_SSH_PORT-10.13.00.03:22 \
  -device virtio-net-pci,netdev=wan0 \
  -netdev user,id=wan0
"
  # Final focus/attach
  if [[ -n "${TMUX:-}" ]]; then
    tmux select-window -t "$TARGET"
    tmux display-message "Launched in window $TARGET"
  else
    tmux attach -t "$SESSION"
  fi
}

wait_for_ssh() {
  local port=$1
  echo "Waiting for SSH on port $port"
  until ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -p "$port" root@127.0.0.1 true 2>/dev/null; do
  sleep 1
  done
  echo "SSH is up on $port"
}

setup_ssh() {
  wait_for_ssh $1
  ssh -o UserKnownHostsFile=/dev/null \
      -o StrictHostKeyChecking=no \
      -p $1 root@127.0.0.1 /bin/sh -s "$HOST_IP" <<'EOSSH'
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
  sleep 1
  wifi up
EOSSH

}

main() {
  prepare_images
  start_tmux_env
  launch
  setup_ssh $VM1_SSH_PORT
  setup_ssh $VM2_SSH_PORT
  setup_ssh $VM3_SSH_PORT
}

main "$@"

