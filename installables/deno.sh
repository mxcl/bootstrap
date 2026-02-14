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
  tmpdir="$(mktemp -d "${UPGRADE_STAGE_DIR}/deno.XXXXXX")"
else
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir}"' EXIT
fi

downloaded="$(
  "${yoink_bin}" -C "${tmpdir}" denoland/deno |
    /usr/bin/head -n 1
)"

if [ -z "${downloaded}" ] || ! [ -f "${downloaded}" ]; then
  echo "deno binary not found after download" >&2
  exit 1
fi

if [ -n "${UPGRADE_STAGE_DIR:-}" ]; then
  staged_bin_dir="${UPGRADE_STAGE_DIR}/bin"
  mkdir -p "${staged_bin_dir}"
  staged_deno="${staged_bin_dir}/deno"
  cp "${downloaded}" "${staged_deno}"
  chmod 755 "${staged_deno}"
  DENO_BIN="${staged_deno}"
  export DENO_BIN
fi

$_SUDO install -m 755 "${downloaded}" /usr/local/bin/deno

if [ -n "${UPGRADE_STAGE_DIR:-}" ]; then
  $_SUDO rm -rf "${tmpdir}"
fi
