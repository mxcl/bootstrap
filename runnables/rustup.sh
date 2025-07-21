#!/bin/sh

set -eo pipefail

CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"

if [ ! -f "$CARGO_HOME/bin/rustup" -a "$1" = init ]; then
  # prevent rustup-init from warning that rust is already installed when it is just us
  export RUSTUP_INIT_SKIP_PATH_CHECK=yes

  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --no-modify-path
  exit $?
elif [ ! -f "$CARGO_HOME/bin/rustup" ]; then
  echo "a \`rustup\` toolchain has not been installed" >&2
  echo "run: \`rustup init\`" >&2
  exit 3
fi

exec "$CARGO_HOME/bin/rustup" "$@"
