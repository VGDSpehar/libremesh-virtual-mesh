#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${1:-}" =~ ^(-h|--help|help)$ ]]; then
  exec "$SCRIPT_DIR/bin/lvm" help
fi

exec "$SCRIPT_DIR/bin/lvm" setup-vm "$@"
