#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$#" -eq 0 ]]; then
  exec "$SCRIPT_DIR/bin/lvm" start-monitor
fi

exec "$SCRIPT_DIR/bin/lvm" "$@"
