#!/bin/sh
set -eo pipefail

yoink_bin="/usr/local/bin/yoink"
if ! [ -x "${yoink_bin}" ]; then
  if command -v yoink >/dev/null 2>&1; then
    yoink_bin="$(command -v yoink)"
  else
    echo "yoink not installed; run installables/yoink.sh" >&2
    exit 1
  fi
fi

$_SUDO "${yoink_bin}" -C /usr/local/bin denoland/deno
