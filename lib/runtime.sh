#!/usr/bin/env bash

lvm_node_name() {
  printf 'node-%s\n' "$1"
}

lvm_monitor_component_name() {
  printf 'monitor\n'
}

lvm_node_ssh_port() {
  local index="$1"
  printf '%s\n' "$((LVM_BASE_SSH_PORT + index - 1))"
}

lvm_node_guest_ip() {
  local index="$1"
  printf '10.13.0.%s\n' "$index"
}

lvm_node_mac() {
  local index="$1"
  printf '52:54:00:00:00:%02x\n' "$index"
}

lvm_monitor_mac() {
  printf '52:54:00:00:00:%02x\n' "$((LVM_NODE_COUNT + 1))"
}

lvm_monitor_guest_ip() {
  printf '10.13.0.%s\n' "$((LVM_NODE_COUNT + 1))"
}

lvm_pid_file() {
  printf '%s/%s.pid\n' "$LVM_PIDS_DIR" "$1"
}

lvm_log_file() {
  printf '%s/%s.log\n' "$LVM_LOG_DIR" "$1"
}

lvm_overlay_path() {
  printf '%s/%s.qcow2\n' "$LVM_DISKS_DIR" "$1"
}

lvm_prepare_runtime_dirs() {
  mkdir -p "$LVM_LOG_DIR" "$LVM_PIDS_DIR" "$LVM_DISKS_DIR" "$LVM_STATE_DIR"
}

lvm_prepare_runtime_logs() {
  local index

  lvm_prepare_component_log vwifi-server
  lvm_prepare_component_log "$(lvm_monitor_component_name)"

  for ((index = 1; index <= LVM_NODE_COUNT; index++)); do
    lvm_prepare_component_log "$(lvm_node_name "$index")"
  done
}

lvm_prepare_component_log() {
  : > "$(lvm_log_file "$1")"
}

lvm_pid_is_running() {
  local pid="$1"
  kill -0 "$pid" 2>/dev/null
}

lvm_component_pid() {
  local component="$1"
  local pid_file pid

  pid_file="$(lvm_pid_file "$component")"
  [[ -f "$pid_file" ]] || return 1

  pid="$(<"$pid_file")"
  [[ -n "$pid" ]] || return 1

  if lvm_pid_is_running "$pid"; then
    printf '%s\n' "$pid"
    return 0
  fi

  rm -f "$pid_file"
  return 1
}

lvm_component_is_running() {
  lvm_component_pid "$1" >/dev/null
}

lvm_cleanup_stale_runtime() {
  local component index

  lvm_prepare_runtime_dirs

  lvm_component_pid vwifi-server >/dev/null 2>&1 || true
  lvm_component_pid "$(lvm_monitor_component_name)" >/dev/null 2>&1 || true

  for ((index = 1; index <= LVM_NODE_COUNT; index++)); do
    component="$(lvm_node_name "$index")"
    lvm_component_pid "$component" >/dev/null 2>&1 || true
  done
}

lvm_any_component_running() {
  local index

  if lvm_component_is_running vwifi-server || lvm_component_is_running "$(lvm_monitor_component_name)"; then
    return 0
  fi

  for ((index = 1; index <= LVM_NODE_COUNT; index++)); do
    if lvm_component_is_running "$(lvm_node_name "$index")"; then
      return 0
    fi
  done

  return 1
}

lvm_start_background_process() {
  local component="$1"
  local log_path="$2"
  local pid_file pid

  shift 2

  if lvm_component_is_running "$component"; then
    lvm_die "$component is already running."
  fi

  pid_file="$(lvm_pid_file "$component")"
  : > "$log_path"

  nohup "$@" >>"$log_path" 2>&1 &
  pid=$!
  printf '%s\n' "$pid" > "$pid_file"

  sleep 1
  if ! lvm_pid_is_running "$pid"; then
    rm -f "$pid_file"
    lvm_error "$component exited immediately. Inspect $log_path for details."
    return 1
  fi

  lvm_log "Started $component (pid $pid)"
}

lvm_stop_component() {
  local component="$1"
  local pid pid_file tries

  pid_file="$(lvm_pid_file "$component")"
  if ! pid="$(lvm_component_pid "$component")"; then
    rm -f "$pid_file"
    return 0
  fi

  kill "$pid" 2>/dev/null || true
  for ((tries = 0; tries < 15; tries++)); do
    if ! lvm_pid_is_running "$pid"; then
      rm -f "$pid_file"
      lvm_log "Stopped $component"
      return 0
    fi
    sleep 1
  done

  lvm_warn "$component did not stop after SIGTERM; sending SIGKILL."
  kill -9 "$pid" 2>/dev/null || true
  rm -f "$pid_file"
}

lvm_runtime_load_state_if_present() {
  if [[ -f "$LVM_STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$LVM_STATE_FILE"
  fi
}

lvm_save_state() {
  local state_vars state_var

  lvm_prepare_runtime_dirs

  state_vars=(
    LVM_NODE_COUNT
    LVM_BASE_SSH_PORT
    LVM_OPENWRT_BUILD_DIR
    LVM_IMAGE_PATH
    LVM_RUNTIME_DIR
    LVM_TMUX_SESSION
    LVM_TMUX_WINDOW
    LVM_TMUX_TARGET
    LVM_VM_MEMORY
    LVM_VM_CPUS
    LVM_QEMU_BIN
    LVM_QEMU_IMG_BIN
    LVM_VWIFI_BIN
    LVM_VWIFI_ARGS
    LVM_MONITOR_SSH_PORT
    LVM_MONITOR_HTTP_PORT
    LVM_ATTACH_TMUX
    LVM_LOG_DIR
    LVM_PIDS_DIR
    LVM_DISKS_DIR
    LVM_STATE_DIR
    LVM_STATE_FILE
    LVM_RAW_IMAGE_PATH
    LVM_MESH_NETWORK
  )

  : > "$LVM_STATE_FILE"
  for state_var in "${state_vars[@]}"; do
    if [[ -v "$state_var" ]]; then
      printf '%s=%q\n' "$state_var" "${!state_var}" >> "$LVM_STATE_FILE"
    fi
  done
}

lvm_remove_runtime_dir() {
  if [[ "$LVM_RUNTIME_DIR" == "/" || -z "$LVM_RUNTIME_DIR" ]]; then
    lvm_die "Refusing to remove unsafe runtime directory '$LVM_RUNTIME_DIR'."
  fi

  rm -rf "$LVM_RUNTIME_DIR"
}
