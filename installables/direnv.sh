#!/bin/sh
set -eo pipefail

yoink_bin="${YOINK_BIN:-/usr/local/bin/yoink}"
if ! [ -x "${yoink_bin}" ]; then
  if command -v yoink >/dev/null 2>&1; then
    yoink_bin="$(command -v yoink)"
  else
    echo "yoink not installed; run installables/yoink.sh" >&2
    exit 1
  fi
fi

if [ -n "${UPGRADE_STAGE_DIR:-}" ]; then
  tmpdir="$(mktemp -d "${UPGRADE_STAGE_DIR}/direnv.XXXXXX")"
else
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir}"' EXIT
fi

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

if [ -n "${UPGRADE_STAGE_DIR:-}" ]; then
  $_SUDO rm -rf "${tmpdir}"
fi
