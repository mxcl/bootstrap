#!/bin/sh
set -eo pipefail

os="$(uname -s)"
arch="$(uname -m)"

case "${os}:${arch}" in
  Darwin:arm64) target="aarch64-apple-darwin" ;;
  Darwin:x86_64) target="x86_64-apple-darwin" ;;
  Linux:aarch64|Linux:arm64) target="aarch64-unknown-linux-gnu" ;;
  Linux:x86_64) target="x86_64-unknown-linux-gnu" ;;
*)
  echo "Unsupported platform: ${os} ${arch}" >&2
  exit 1
  ;;
esac

version="$(
  curl -fsSL https://api.github.com/repos/denoland/deno/releases/latest |
    /usr/bin/jq -r '.tag_name'
)"

asset="deno-${target}.zip"
url="https://github.com/denoland/deno/releases/download/${version}/${asset}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

curl -fsSL "${url}" -o "${tmpdir}/${asset}"
unzip -q "${tmpdir}/${asset}" -d "${tmpdir}"

$_SUDO install -m 755 "${tmpdir}/deno" /usr/local/bin/deno
