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

paths="$("${yoink_bin}" -C "${tmpdir}" astral-sh/uv)"
if [ -z "${paths}" ]; then
  echo "Unable to download uv" >&2
  exit 1
fi

set -- ${paths}
for path in "$@"; do
  if [ -z "${path}" ] || ! [ -f "${path}" ]; then
    echo "uv binary not found after download" >&2
    exit 1
  fi
  $_SUDO install -m 755 "${path}" "/usr/local/bin/$(basename "${path}")"
done
