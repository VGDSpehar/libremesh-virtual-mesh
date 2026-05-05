#!/usr/bin/env bash

lvm_tmux_create_mesh_window() {
  local target
  local logs=()
  local index

  target="$(lvm_tmux_create_window)"

  logs+=("$(lvm_log_file vwifi-server)")
  for ((index = 1; index <= LVM_NODE_COUNT; index++)); do
    logs+=("$(lvm_log_file "$(lvm_node_name "$index")")")
  done

  lvm_tmux_populate_window "$target" "${logs[@]}"
  printf '%s\n' "$target"
}

lvm_tmux_create_window() {
  local target

  if [[ -n "${TMUX:-}" ]]; then
    target="$(tmux new-window -a -P -F '#{session_name}:#{window_index}' -n "$LVM_TMUX_WINDOW" -c "$LVM_ROOT_DIR")"
  elif tmux has-session -t "$LVM_TMUX_SESSION" 2>/dev/null; then
    target="$(tmux new-window -a -P -F '#{session_name}:#{window_index}' -t "$LVM_TMUX_SESSION" -n "$LVM_TMUX_WINDOW" -c "$LVM_ROOT_DIR")"
  else
    target="$(tmux new-session -d -P -F '#{session_name}:#{window_index}' -s "$LVM_TMUX_SESSION" -n "$LVM_TMUX_WINDOW" -c "$LVM_ROOT_DIR")"
  fi

  printf '%s\n' "$target"
}

lvm_tmux_populate_window() {
  local target="$1"
  local pane_count pane_index pane_target shell_pane log_path command

  shift
  pane_count=$(($# + 1))

  for ((pane_index = 1; pane_index < pane_count; pane_index++)); do
    tmux split-window -d -t "$target" -c "$LVM_ROOT_DIR"
    tmux select-layout -t "$target" tiled >/dev/null
  done

  pane_index=0
  for log_path in "$@"; do
    pane_target="$target.$pane_index"
    command="clear; printf 'Log: %s\n\n' '$log_path'; tail -F '$log_path'"
    tmux send-keys -t "$pane_target" "$command" C-m
    pane_index=$((pane_index + 1))
  done

  shell_pane="$target.$pane_index"
  command="clear; printf 'Runtime: %s\n' '$LVM_RUNTIME_DIR'; printf 'Use ./bin/lvm status for an overview.\n'"
  tmux send-keys -t "$shell_pane" "$command" C-m
  tmux select-layout -t "$target" tiled >/dev/null
}

lvm_tmux_attach_or_select() {
  local target="$1"

  if [[ -n "${TMUX:-}" ]]; then
    tmux select-window -t "$target"
    return 0
  fi

  if [[ "${LVM_ATTACH_TMUX}" == "1" ]]; then
    tmux attach -t "${target%%:*}"
  fi
}

lvm_tmux_target_is_active() {
  local target="${1:-}"

  [[ -n "$target" ]] || return 1
  tmux list-windows -t "${target%%:*}" -F '#{session_name}:#{window_index}' 2>/dev/null | grep -Fx -- "$target" >/dev/null
}

lvm_tmux_kill_target_if_present() {
  local target="${1:-}"

  if lvm_tmux_target_is_active "$target"; then
    tmux kill-window -t "$target"
  fi
}
