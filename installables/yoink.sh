#!/bin/sh
set -eo pipefail

if [ -n "${UPGRADE_STAGE_DIR:-}" ]; then
  tmpdir="$(mktemp -d "${UPGRADE_STAGE_DIR}/yoink.XXXXXX")"
  install_script="${tmpdir}/install.sh"
  curl -fsSL https://yoink.sh -o "${install_script}"
  staged_bin_dir="${UPGRADE_STAGE_DIR}/bin"
  mkdir -p "${staged_bin_dir}"
  yoink_path="$(
    sh "${install_script}" -C "${staged_bin_dir}" mxcl/yoink |
      /usr/bin/head -n 1
  )"
  if [ -z "${yoink_path}" ] || ! [ -x "${yoink_path}" ]; then
    echo "yoink binary not found after download" >&2
    exit 1
  fi
  YOINK_BIN="${yoink_path}"
  export YOINK_BIN
  $_SUDO install -m 755 "${yoink_path}" /usr/local/bin/yoink
  $_SUDO rm -rf "${tmpdir}"
else
  curl -fsSL https://yoink.sh |
    $_SUDO sh -s -- -C /usr/local/bin mxcl/yoink
fi
