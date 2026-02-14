#!/bin/sh
set -euo pipefail

extract_version() {
  /usr/bin/awk '
    match($0, /v?[0-9]+([.][0-9]+)*/) {
      print substr($0, RSTART, RLENGTH)
      exit
    }
  '
}

sanitize_version() {
  printf '%s' "$1" | /usr/bin/sed -E 's/^[^0-9]*//; s/[^0-9.].*$//'
}

version_is_newer() {
  latest="$(sanitize_version "$1")"
  current="$(sanitize_version "$2")"

  if [ -z "${latest}" ] || [ -z "${current}" ]; then
    return 0
  fi

  /usr/bin/awk -v a="${latest}" -v b="${current}" '
    function splitver(v, arr,    i, n) {
      n = split(v, arr, ".");
      for (i = 1; i <= n; i++) if (arr[i] == "") arr[i] = 0;
      return n;
    }
    BEGIN {
      na = splitver(a, A);
      nb = splitver(b, B);
      n = (na > nb) ? na : nb;
      for (i = 1; i <= n; i++) {
        ai = (i <= na) ? A[i] : 0;
        bi = (i <= nb) ? B[i] : 0;
        if (ai + 0 > bi + 0) exit 0;
        if (ai + 0 < bi + 0) exit 1;
      }
      exit 2;
    }'

  case $? in
    0) return 0 ;;
    *) return 1 ;;
  esac
}

latest_tag() {
  repo="$1"
  tag="$(
    curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" |
      /usr/bin/awk '
        match($0, /"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"/) {
          value = substr($0, RSTART, RLENGTH)
          sub(/^.*:[[:space:]]*"/, "", value)
          sub(/"$/, "", value)
          print value
          exit
        }'
  )"

  if [ -z "${tag}" ] || [ "${tag}" = "null" ]; then
    echo "Unable to determine latest release for ${repo}" >&2
    return 2
  fi

  printf '%s\n' "${tag}"
}

installed_version() {
  bin="$1"

  if [ -x "${bin}" ]; then
    "${bin}" --version 2>/dev/null | extract_version || true
  fi
}
