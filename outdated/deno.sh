#!/bin/sh
set -euo pipefail

script_path="$(command -v "$0" 2>/dev/null || printf '%s' "$0")"
script_dir="$(CDPATH= cd -- "$(dirname -- "${script_path}")" && pwd)"

. "${script_dir}/lib.sh"

repo="denoland/deno"
bin="/usr/local/bin/deno"

latest="$(latest_tag "${repo}")"

if [ -z "${latest}" ] || [ "${latest}" = "null" ]; then
  echo "Unable to determine latest release for ${repo}" >&2
  exit 2
fi

installed="$(installed_version "${bin}")"

if [ -n "${installed}" ] && ! version_is_newer "${latest}" "${installed}"; then
  exit 1
fi

printf '%s\n' "${latest}"
