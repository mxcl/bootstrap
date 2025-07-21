#!/bin/sh
set -eo pipefail

os="$(uname -s)"
arch="$(uname -m)"

case "${os}:${arch}" in
  Darwin:arm64) target="darwin+aarch64" ;;
  Darwin:x86_64) target="darwin+x86-64" ;;
  Linux:aarch64|Linux:arm64) target="linux+aarch64" ;;
  Linux:x86_64) target="linux+x86-64" ;;
*)
  echo "Unsupported platform: ${os} ${arch}" >&2
  exit 1
  ;;
esac

version="$(
  curl -fsSL https://api.github.com/repos/pkgxdev/pkgx/releases/latest |
    /usr/bin/jq -r '.tag_name'
)"

plain_version="${version#v}"
asset="pkgx-${plain_version}+${target}.tar.gz"
url="https://github.com/pkgxdev/pkgx/releases/download/${version}/${asset}"

curl -fsSL "${url}" | $_SUDO tar -xzf - -C /usr/local/bin
