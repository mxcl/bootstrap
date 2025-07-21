#!/bin/sh
set -eo pipefail

os="$(uname -s)"
arch="$(uname -m)"

case "${os}:${arch}" in
  Darwin:arm64) target="aarch64-apple-darwin" ;;
  Darwin:x86_64) target="x86_64-apple-darwin" ;;
  Linux:x86_64) target="x86_64-unknown-linux-gnu" ;;
*)
  echo "Unsupported platform: ${os} ${arch}" >&2
  exit 1
  ;;
esac

version="$(
  curl -fsSL https://api.github.com/repos/pkgxdev/cargox/releases/latest |
    /usr/bin/jq -r '.tag_name'
)"

plain_version="${version#v}"
asset="cargox-${plain_version}-${target}.tar.gz"
url="https://github.com/pkgxdev/cargox/releases/download/${version}/${asset}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

curl -fsSL "${url}" | tar -xzf - -C "${tmpdir}"

$_SUDO install -m 755 "${tmpdir}/cargox" /usr/local/bin/cargox
