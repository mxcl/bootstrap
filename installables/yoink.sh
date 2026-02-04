#!/bin/sh
set -eo pipefail

os="$(uname -s)"
arch="$(uname -m)"

case "${os}:${arch}" in
  Darwin:arm64) asset_os="Darwin"; asset_arch="arm64" ;;
  Darwin:x86_64) asset_os="Darwin"; asset_arch="x86_64" ;;
  Linux:aarch64|Linux:arm64) asset_os="Linux"; asset_arch="aarch64" ;;
  Linux:x86_64) asset_os="Linux"; asset_arch="x86_64" ;;
  *)
    echo "Unsupported platform: ${os} ${arch}" >&2
    exit 1
    ;;
esac

version="$(
  curl -fsSL https://api.github.com/repos/mxcl/yoink/releases/latest |
    /usr/bin/jq -r '.tag_name'
)"

if [ -z "${version}" ] || [ "${version}" = "null" ]; then
  echo "Unable to determine latest yoink version" >&2
  exit 1
fi

plain_version="${version#v}"
asset="yoink-${plain_version}-${asset_os}-${asset_arch}.tar.gz"
url="https://github.com/mxcl/yoink/releases/download/${version}/${asset}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

curl -fsSL "${url}" | tar -xzf - -C "${tmpdir}"

if ! [ -f "${tmpdir}/yoink" ]; then
  echo "yoink binary not found in archive" >&2
  exit 1
fi

$_SUDO install -m 755 "${tmpdir}/yoink" /usr/local/bin/yoink
