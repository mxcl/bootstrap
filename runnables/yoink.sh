#!/bin/sh

set -eo pipefail

YOINK_BIN_DIR="${YOINK_BIN_DIR:-$HOME/.local/bin}"
YOINK_BIN="${YOINK_BIN_DIR}/yoink"

if [ ! -x "$YOINK_BIN" ]; then
  mkdir -p "$YOINK_BIN_DIR"
  curl -fsSL https://yoink.sh | YOINK_BIN_DIR="$YOINK_BIN_DIR" sh -s -- mxcl/yoink
fi

exec "$YOINK_BIN" "$@"
