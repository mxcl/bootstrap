#!/bin/sh
set -eo pipefail

if [ -n "${UPGRADE_STAGE_DIR:-}" ]; then
  tmpdir="$(mktemp -d "${UPGRADE_STAGE_DIR}/yoink.XXXXXX")"
  install_script="${tmpdir}/install.sh"
  curl -fsSL https://yoink.sh -o "${install_script}"
  $_SUDO sh "${install_script}" -C /usr/local/bin mxcl/yoink
  $_SUDO rm -rf "${tmpdir}"
else
  curl -fsSL https://yoink.sh |
    $_SUDO sh -s -- -C /usr/local/bin mxcl/yoink
fi
