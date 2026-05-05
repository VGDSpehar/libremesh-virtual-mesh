#!/usr/bin/env bash

lvm_prepare_base_image() {
  local tmp_image gzip_status

  if [[ -f "$LVM_RAW_IMAGE_PATH" && "$LVM_RAW_IMAGE_PATH" -nt "$LVM_IMAGE_PATH" ]]; then
    return 0
  fi

  lvm_log "Decompressing base image to $LVM_RAW_IMAGE_PATH"
  tmp_image="${LVM_RAW_IMAGE_PATH}.tmp"
  rm -f "$tmp_image"

  set +e
  gzip -dc "$LVM_IMAGE_PATH" > "$tmp_image"
  gzip_status=$?
  set -e

  if [[ "$gzip_status" -ne 0 && "$gzip_status" -ne 2 ]]; then
    rm -f "$tmp_image"
    lvm_die "Failed to decompress $LVM_IMAGE_PATH (gzip exit $gzip_status)."
  fi

  mv "$tmp_image" "$LVM_RAW_IMAGE_PATH"
}

lvm_prepare_overlay() {
  local component="$1"
  local overlay_path

  overlay_path="$(lvm_overlay_path "$component")"
  if [[ -f "$overlay_path" && "$LVM_RAW_IMAGE_PATH" -nt "$overlay_path" ]]; then
    rm -f "$overlay_path"
  fi

  if [[ ! -f "$overlay_path" ]]; then
    lvm_log "Creating overlay $overlay_path"
    "$LVM_QEMU_IMG_BIN" create -f qcow2 -F raw -b "$LVM_RAW_IMAGE_PATH" "$overlay_path" >/dev/null
  fi
}

lvm_prepare_vm_images() {
  local index

  lvm_prepare_base_image
  for ((index = 1; index <= LVM_NODE_COUNT; index++)); do
    lvm_prepare_overlay "$(lvm_node_name "$index")"
  done
  lvm_prepare_overlay "$(lvm_monitor_component_name)"
}

lvm_prepare_monitor_image() {
  lvm_prepare_base_image
  lvm_prepare_overlay "$(lvm_monitor_component_name)"
}

lvm_launch_node_vm() {
  local index="$1"
  local component guest_ip mac ssh_port overlay_path
  local -a command

  component="$(lvm_node_name "$index")"
  overlay_path="$(lvm_overlay_path "$component")"
  guest_ip="$(lvm_node_guest_ip "$index")"
  mac="$(lvm_node_mac "$index")"
  ssh_port="$(lvm_node_ssh_port "$index")"

  command=(
    "$LVM_QEMU_BIN"
    -enable-kvm
    -M q35
    -cpu host
    -smp "$LVM_VM_CPUS"
    -m "${LVM_VM_MEMORY}M"
    -nographic
    -drive "file=$overlay_path,if=virtio,format=qcow2"
    -device "virtio-net-pci,mac=$mac,netdev=mesh0"
    -netdev "user,id=mesh0,net=$LVM_MESH_NETWORK,hostfwd=tcp::${ssh_port}-${guest_ip}:22"
    -device "virtio-net-pci,netdev=wan0"
    -netdev "$LVM_WAN_NETDEV"
  )

  lvm_start_background_process "$component" "$(lvm_log_file "$component")" "${command[@]}"
}

lvm_start_mesh_nodes() {
  local index

  for ((index = 1; index <= LVM_NODE_COUNT; index++)); do
    lvm_launch_node_vm "$index" || return 1
  done
}

lvm_start_monitor_vm() {
  local component guest_ip mac overlay_path
  local -a command

  component="$(lvm_monitor_component_name)"
  overlay_path="$(lvm_overlay_path "$component")"
  guest_ip="$(lvm_monitor_guest_ip)"
  mac="$(lvm_monitor_mac)"

  command=(
    "$LVM_QEMU_BIN"
    -enable-kvm
    -M q35
    -cpu host
    -smp "$LVM_VM_CPUS"
    -m "${LVM_VM_MEMORY}M"
    -nographic
    -drive "file=$overlay_path,if=virtio,format=qcow2"
    -device "virtio-net-pci,mac=$mac,netdev=mesh0"
    -netdev "user,id=mesh0,net=$LVM_MESH_NETWORK,hostfwd=tcp::${LVM_MONITOR_SSH_PORT}-${guest_ip}:22,hostfwd=tcp::${LVM_MONITOR_HTTP_PORT}-${guest_ip}:80"
    -device "virtio-net-pci,netdev=wan0"
    -netdev "$LVM_WAN_NETDEV"
  )

  lvm_start_background_process "$component" "$(lvm_log_file "$component")" "${command[@]}"
}

lvm_wait_for_ssh() {
  local port="$1"
  local timeout="${2:-120}"
  local elapsed=0

  lvm_log "Waiting for SSH on port $port"
  until ssh "${LVM_SSH_OPTS[@]}" -p "$port" root@127.0.0.1 true >/dev/null 2>&1; do
    sleep 1
    elapsed=$((elapsed + 1))
    if (( elapsed >= timeout )); then
      lvm_die "Timed out waiting for SSH on port $port."
    fi
  done

  lvm_log "SSH is reachable on port $port"
}

lvm_host_ipv4() {
  local host_ipv4

  host_ipv4="$(ip -o -4 addr show scope global | awk '{split($4, fields, "/"); print fields[1]; exit}')"
  [[ -n "$host_ipv4" ]] || lvm_die "Could not detect a host IPv4 address."
  printf '%s\n' "$host_ipv4"
}

lvm_setup_vm_by_port() {
  local port="${1:-}"
  local host_ipv4

  [[ -n "$port" ]] || lvm_die "Usage: ./bin/lvm setup-vm <ssh-port>"

  host_ipv4="$(lvm_host_ipv4)"
  lvm_wait_for_ssh "$port"

ssh "${LVM_SSH_OPTS[@]}" -p "$port" root@127.0.0.1 /bin/sh -s "$host_ipv4" <<'EOSSH'
set -eux
service vwifi-client stop

LAST_OCT=$(cut -d: -f6 < /sys/class/net/eth0/address)

uci set lime-node.network.main_ipv4_address="172.31.0.0/16"

uci set vwifi.config.server_ip="$1"
uci set vwifi.config.mac_prefix="02:00:00:00:00:${LAST_OCT}"
uci set vwifi.config.enabled='1'
uci commit vwifi

service vwifi-client start
wifi config
lime-config
wifi down
sleep 7
wifi up
EOSSH
}
