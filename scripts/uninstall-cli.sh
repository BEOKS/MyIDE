#!/usr/bin/env bash
set -euo pipefail

DEFAULT_PREFIX="${HOME}/.local/bin"
PREFIX="${1:-$DEFAULT_PREFIX}"
TARGET_BINARY="${PREFIX}/MyIDECLI"

if [[ -L "${TARGET_BINARY}" || -f "${TARGET_BINARY}" ]]; then
  rm -f "${TARGET_BINARY}"
  echo "Removed ${TARGET_BINARY}"
else
  echo "No installed MyIDECLI found at ${TARGET_BINARY}"
fi
