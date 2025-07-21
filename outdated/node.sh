#!/bin/sh
set -euo pipefail

script_path="$(command -v "$0" 2>/dev/null || printf '%s' "$0")"
script_dir="$(CDPATH= cd -- "$(dirname -- "${script_path}")" && pwd)"

. "${script_dir}/lib.sh"

bin="/usr/local/bin/node"

latest="$(
  curl -fsSL https://nodejs.org/dist/index.json |
    /usr/bin/jq -r '.[0].version'
)"

if [ -z "${latest}" ] || [ "${latest}" = "null" ]; then
  echo "Unable to determine latest node version" >&2
  exit 2
fi

installed="$(installed_version "${bin}")"

if [ -n "${installed}" ] && ! version_is_newer "${latest}" "${installed}"; then
  exit 1
fi

printf '%s\n' "${latest}"
