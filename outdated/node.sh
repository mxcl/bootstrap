#!/bin/sh
set -euo pipefail

script_path="$(command -v "$0" 2>/dev/null || printf '%s' "$0")"
script_dir="$(CDPATH= cd -- "$(dirname -- "${script_path}")" && pwd)"

. "${script_dir}/lib.sh"

bin="/usr/local/bin/node"

yoink_bin="/usr/local/bin/yoink"
if ! [ -x "${yoink_bin}" ]; then
  if command -v yoink >/dev/null 2>&1; then
    yoink_bin="$(command -v yoink)"
  else
    echo "yoink not installed; unable to check nodejs/node" >&2
    exit 2
  fi
fi

latest="$("${yoink_bin}" -jI nodejs/node | /usr/bin/jq -r '.tag')"

if [ -z "${latest}" ] || [ "${latest}" = "null" ]; then
  echo "Unable to determine latest node version" >&2
  exit 2
fi

installed="$(installed_version "${bin}")"

if [ -n "${installed}" ] && ! version_is_newer "${latest}" "${installed}"; then
  exit 1
fi

printf '%s\n' "${latest}"
