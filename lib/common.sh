#!/usr/bin/env bash

lvm_log() {
  printf '[INFO] %s\n' "$*" >&2
}

lvm_warn() {
  printf '[WARN] %s\n' "$*" >&2
}

lvm_error() {
  printf '[ERROR] %s\n' "$*" >&2
}

lvm_die() {
  lvm_error "$*"
  exit 1
}

lvm_abs_path() {
  local path="$1"
  local base_dir="${2:-$PWD}"

  if [[ "$path" = /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s/%s\n' "$base_dir" "$path"
  fi
}

lvm_is_integer() {
  [[ "${1:-}" =~ ^[0-9]+$ ]]
}

lvm_command_available() {
  local command_name="$1"

  if [[ "$command_name" == */* ]]; then
    [[ -x "$command_name" ]]
  else
    command -v "$command_name" >/dev/null 2>&1
  fi
}
