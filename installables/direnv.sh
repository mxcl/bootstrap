#!/bin/sh
set -eo pipefail

os="$(uname -s)"
arch="$(uname -m)"

case "${os}:${arch}" in
  Darwin:arm64) target_os="darwin"; target_arch="arm64" ;;
  Darwin:x86_64) target_os="darwin"; target_arch="amd64" ;;
  Linux:aarch64|Linux:arm64) target_os="linux"; target_arch="arm64" ;;
  Linux:x86_64) target_os="linux"; target_arch="amd64" ;;
*)
  echo "Unsupported platform: ${os} ${arch}" >&2
  exit 1
  ;;
esac

direnv_version="${1:-}"
if [ -z "${direnv_version}" ]; then
  direnv_version="$(
    curl -fsSL https://api.github.com/repos/direnv/direnv/releases/latest |
      /usr/bin/jq -r '.tag_name'
  )"
fi

if [ -z "${direnv_version}" ] || [ "${direnv_version}" = "null" ]; then
  echo "Unable to determine latest direnv version" >&2
  exit 1
fi

asset="direnv.${target_os}-${target_arch}"
url="https://github.com/direnv/direnv/releases/download/${direnv_version}/${asset}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

curl -fsSL "${url}" -o "${tmpdir}/${asset}"

$_SUDO install -m 755 "${tmpdir}/${asset}" /usr/local/bin/direnv
