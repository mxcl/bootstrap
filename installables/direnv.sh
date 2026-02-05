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

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

downloaded="$(
  "${yoink_bin}" -C "${tmpdir}" direnv/direnv |
    /usr/bin/head -n 1
)"

if [ -z "${downloaded}" ] || ! [ -f "${downloaded}" ]; then
  echo "direnv binary not found after download" >&2
  exit 1
fi

tmpbin="${tmpdir}/direnv"
if [ "${downloaded}" != "${tmpbin}" ]; then
  mv "${downloaded}" "${tmpbin}"
fi

$_SUDO install -m 755 "${tmpbin}" /usr/local/bin/direnv
