#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_PREFIX="${HOME}/.local/bin"
PREFIX="${1:-$DEFAULT_PREFIX}"
BINARY_NAME="MyIDECLI"
SOURCE_BINARY="${ROOT_DIR}/.build/release/${BINARY_NAME}"
TARGET_BINARY="${PREFIX}/${BINARY_NAME}"

echo "Building ${BINARY_NAME} in release mode..."
swift build -c release --product "${BINARY_NAME}" --package-path "${ROOT_DIR}"

mkdir -p "${PREFIX}"
ln -sf "${SOURCE_BINARY}" "${TARGET_BINARY}"

echo "Installed ${BINARY_NAME} to ${TARGET_BINARY}"

case ":${PATH}:" in
  *":${PREFIX}:"*)
    echo "${PREFIX} is already on PATH."
    ;;
  *)
    echo "Add this to your shell profile if needed:"
    echo "export PATH=\"${PREFIX}:\$PATH\""
    ;;
esac

echo "Verify with:"
echo "${BINARY_NAME} help"
