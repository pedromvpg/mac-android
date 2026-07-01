#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
TARGET="${BIN_DIR}/mac-android"

mkdir -p "$BIN_DIR"
ln -sf "${ROOT}/bin/mac-android" "$TARGET"
ln -sf "${ROOT}/bin/mac-android-gui" "${BIN_DIR}/mac-android-gui"
chmod +x "${ROOT}/bin/mac-android" "${ROOT}/bin/mac-android-gui"

if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
  echo "Added symlink: $TARGET"
  echo
  echo "Add ~/.local/bin to your PATH (if not already):"
  echo '  echo '\''export PATH="$HOME/.local/bin:$PATH"'\'' >> ~/.zshrc'
  echo '  source ~/.zshrc'
else
  echo "Installed: $TARGET"
fi

echo
echo "Next steps:"
echo "  mac-android setup"
echo "  mac-android devices"
