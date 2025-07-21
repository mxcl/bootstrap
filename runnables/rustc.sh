#!/bin/sh

set -eo pipefail

CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"

if [ ! -f "$CARGO_HOME/bin/rustup" ]; then
  echo "a \`rustup\` toolchain has not been installed" >&2
  echo "run: \`rustup init\`" >&2
  exit 3
fi

#TODO path might be different
source "$CARGO_HOME/env"

exec "$CARGO_HOME/bin/rustc" "$@"
