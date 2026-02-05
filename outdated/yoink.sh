#!/bin/sh
set -euo pipefail

script_path="$(command -v "$0" 2>/dev/null || printf '%s' "$0")"
script_dir="$(CDPATH= cd -- "$(dirname -- "${script_path}")" && pwd)"

. "${script_dir}/lib.sh"

repo="mxcl/yoink"
bin="/usr/local/bin/yoink"

yoink_bin="/usr/local/bin/yoink"
if ! [ -x "${yoink_bin}" ]; then
  if command -v yoink >/dev/null 2>&1; then
    yoink_bin="$(command -v yoink)"
  else
    latest="$(latest_tag "${repo}")"
  fi
fi

if [ -x "${yoink_bin}" ]; then
  latest="$("${yoink_bin}" -jI "${repo}" | /usr/bin/jq -r '.tag')"
fi

if [ -z "${latest:-}" ] || [ "${latest}" = "null" ]; then
  echo "Unable to determine latest release for ${repo}" >&2
  exit 2
fi
installed="$(installed_version "${bin}")"

if [ -n "${installed}" ] && ! version_is_newer "${latest}" "${installed}"; then
  exit 1
fi

printf '%s\n' "${latest}"
