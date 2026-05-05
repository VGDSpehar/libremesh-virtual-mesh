#!/usr/bin/env bash

lvm_dependency_hint() {
  case "$1" in
    qemu-system-x86_64)
      printf '%s\n' "Install QEMU system packages so 'qemu-system-x86_64' is available in PATH."
      ;;
    qemu-img)
      printf '%s\n' "Install QEMU utilities so 'qemu-img' is available in PATH."
      ;;
    tmux)
      printf '%s\n' "Install tmux to manage the runtime log panes."
      ;;
    ssh)
      printf '%s\n' "Install the OpenSSH client package."
      ;;
    ip)
      printf '%s\n' "Install iproute2 so the host IPv4 address can be detected."
      ;;
    gzip)
      printf '%s\n' "Install gzip to unpack the OpenWrt/LibreMesh disk image."
      ;;
    vwifi-server)
      printf '%s\n' "Build or install vwifi-server and ensure it is available in PATH."
      ;;
    *)
      printf '%s\n' "Install '$1' and ensure it is available in PATH."
      ;;
  esac
}

lvm_require_command() {
  local command_name="$1"

  if ! lvm_command_available "$command_name"; then
    lvm_die "Missing dependency '$command_name'. $(lvm_dependency_hint "$command_name")"
  fi
}

lvm_check_image_path() {
  if [[ ! -f "$LVM_IMAGE_PATH" ]]; then
    lvm_die "LibreMesh image not found at '$LVM_IMAGE_PATH'. Set LVM_IMAGE_PATH or LVM_OPENWRT_BUILD_DIR to the correct OpenWrt build directory."
  fi
}

lvm_check_start_dependencies() {
  lvm_require_command gzip
  lvm_require_command "$LVM_QEMU_BIN"
  lvm_require_command "$LVM_QEMU_IMG_BIN"
  lvm_require_command tmux
  lvm_require_command ssh
  lvm_require_command ip
  lvm_require_command "$LVM_VWIFI_BIN"
  lvm_check_image_path
}

lvm_check_setup_dependencies() {
  lvm_require_command ssh
  lvm_require_command ip
}

lvm_check_monitor_dependencies() {
  lvm_require_command "$LVM_QEMU_BIN"
  lvm_require_command "$LVM_QEMU_IMG_BIN"
  lvm_check_image_path
}
