#!/usr/bin/env bash

LVM_CONFIG_OVERRIDE_VARS=(
  LVM_NODE_COUNT
  LVM_BASE_SSH_PORT
  LVM_OPENWRT_BUILD_DIR
  LVM_IMAGE_PATH
  LVM_RUNTIME_DIR
  LVM_TMUX_SESSION
  LVM_TMUX_WINDOW
  LVM_VM_MEMORY
  LVM_VM_CPUS
  LVM_QEMU_BIN
  LVM_QEMU_IMG_BIN
  LVM_VWIFI_BIN
  LVM_VWIFI_ARGS
  LVM_MONITOR_SSH_PORT
  LVM_MONITOR_HTTP_PORT
  LVM_ATTACH_TMUX
)

lvm_capture_env_overrides() {
  LVM_CAPTURED_OVERRIDE_VARS=()
  LVM_CAPTURED_OVERRIDE_VALUES=()

  local var_name
  for var_name in "${LVM_CONFIG_OVERRIDE_VARS[@]}"; do
    if [[ -v "$var_name" ]]; then
      LVM_CAPTURED_OVERRIDE_VARS+=("$var_name")
      LVM_CAPTURED_OVERRIDE_VALUES+=("${!var_name}")
    fi
  done
}

lvm_restore_env_overrides() {
  local index var_name

  for index in "${!LVM_CAPTURED_OVERRIDE_VARS[@]}"; do
    var_name="${LVM_CAPTURED_OVERRIDE_VARS[$index]}"
    printf -v "$var_name" '%s' "${LVM_CAPTURED_OVERRIDE_VALUES[$index]}"
    export "$var_name"
  done
}

lvm_load_config() {
  local default_build_dir

  lvm_capture_env_overrides

  LVM_PROJECT_NAME="libremesh-virtual-mesh"
  LVM_CONFIG_DIR="$LVM_ROOT_DIR/config"

  if [[ -f "$LVM_CONFIG_DIR/default.conf" ]]; then
    # shellcheck source=config/default.conf
    source "$LVM_CONFIG_DIR/default.conf"
  fi

  if [[ -f "$LVM_CONFIG_DIR/local.conf" ]]; then
    # shellcheck source=config/local.conf
    source "$LVM_CONFIG_DIR/local.conf"
  fi

  lvm_restore_env_overrides

  : "${LVM_NODE_COUNT:=3}"
  : "${LVM_BASE_SSH_PORT:=2201}"
  : "${LVM_RUNTIME_DIR:=/tmp/libremesh-virtual-mesh}"
  : "${LVM_TMUX_SESSION:=libremesh_mesh}"
  : "${LVM_TMUX_WINDOW:=virtual-mesh}"
  : "${LVM_VM_MEMORY:=512}"
  : "${LVM_VM_CPUS:=2}"
  : "${LVM_QEMU_BIN:=qemu-system-x86_64}"
  : "${LVM_QEMU_IMG_BIN:=qemu-img}"
  : "${LVM_VWIFI_BIN:=vwifi-server}"
  : "${LVM_VWIFI_ARGS:=-u}"
  : "${LVM_ATTACH_TMUX:=1}"
  : "${LVM_MONITOR_HTTP_PORT:=8004}"

  default_build_dir="$(cd "$LVM_ROOT_DIR/.." && pwd)"
  : "${LVM_OPENWRT_BUILD_DIR:=$default_build_dir}"
  : "${LVM_IMAGE_PATH:=$LVM_OPENWRT_BUILD_DIR/bin/targets/x86/64/openwrt-x86-64-generic-ext4-combined.img.gz}"
  : "${LVM_MONITOR_SSH_PORT:=$((LVM_BASE_SSH_PORT + LVM_NODE_COUNT))}"

  LVM_RUNTIME_DIR="$(lvm_abs_path "$LVM_RUNTIME_DIR")"
  LVM_OPENWRT_BUILD_DIR="$(lvm_abs_path "$LVM_OPENWRT_BUILD_DIR")"
  LVM_IMAGE_PATH="$(lvm_abs_path "$LVM_IMAGE_PATH" "$LVM_OPENWRT_BUILD_DIR")"

  LVM_LOG_DIR="$LVM_RUNTIME_DIR/logs"
  LVM_PIDS_DIR="$LVM_RUNTIME_DIR/pids"
  LVM_DISKS_DIR="$LVM_RUNTIME_DIR/disks"
  LVM_STATE_DIR="$LVM_RUNTIME_DIR/state"
  LVM_STATE_FILE="$LVM_STATE_DIR/runtime.env"
  LVM_RAW_IMAGE_PATH="$LVM_DISKS_DIR/base.img"
  LVM_MESH_NETWORK="10.13.0.0/16"
  LVM_WAN_NETDEV="user,id=wan0"
  LVM_SSH_OPTS=(
    -o UserKnownHostsFile=/dev/null
    -o StrictHostKeyChecking=no
    -o ConnectTimeout=2
  )
}

lvm_validate_config() {
  local int_var

  for int_var in \
    LVM_NODE_COUNT \
    LVM_BASE_SSH_PORT \
    LVM_VM_MEMORY \
    LVM_VM_CPUS \
    LVM_MONITOR_SSH_PORT \
    LVM_MONITOR_HTTP_PORT; do
    if ! lvm_is_integer "${!int_var}"; then
      lvm_die "$int_var must be a positive integer. Current value: ${!int_var}"
    fi
  done

  (( LVM_NODE_COUNT >= 1 )) || lvm_die "LVM_NODE_COUNT must be at least 1."
  (( LVM_VM_MEMORY >= 64 )) || lvm_die "LVM_VM_MEMORY must be at least 64 MB."
  (( LVM_VM_CPUS >= 1 )) || lvm_die "LVM_VM_CPUS must be at least 1."
  (( LVM_BASE_SSH_PORT >= 1 && LVM_BASE_SSH_PORT <= 65535 )) || lvm_die "LVM_BASE_SSH_PORT must be between 1 and 65535."
  (( LVM_MONITOR_SSH_PORT >= 1 && LVM_MONITOR_SSH_PORT <= 65535 )) || lvm_die "LVM_MONITOR_SSH_PORT must be between 1 and 65535."
  (( LVM_MONITOR_HTTP_PORT >= 1 && LVM_MONITOR_HTTP_PORT <= 65535 )) || lvm_die "LVM_MONITOR_HTTP_PORT must be between 1 and 65535."

  [[ -n "$LVM_TMUX_SESSION" ]] || lvm_die "LVM_TMUX_SESSION must not be empty."
  [[ -n "$LVM_TMUX_WINDOW" ]] || lvm_die "LVM_TMUX_WINDOW must not be empty."
  [[ -n "$LVM_IMAGE_PATH" ]] || lvm_die "LVM_IMAGE_PATH must not be empty."
  [[ -n "$LVM_RUNTIME_DIR" ]] || lvm_die "LVM_RUNTIME_DIR must not be empty."
}
