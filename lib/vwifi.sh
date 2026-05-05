#!/usr/bin/env bash

lvm_start_vwifi() {
  local component="vwifi-server"
  local -a command

  command=("$LVM_VWIFI_BIN")
  if [[ -n "$LVM_VWIFI_ARGS" ]]; then
    # shellcheck disable=SC2206
    command+=($LVM_VWIFI_ARGS)
  fi

  lvm_start_background_process "$component" "$(lvm_log_file "$component")" "${command[@]}"
}

lvm_stop_vwifi() {
  lvm_stop_component vwifi-server
}
