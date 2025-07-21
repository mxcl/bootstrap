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
  curl -fsSL https://api.github.com/repos/astral-sh/uv/releases/latest |
    /usr/bin/jq -r '.tag_name'
)"

url="https://github.com/astral-sh/uv/releases/download/${version}/uv-${target}.tar.gz"

curl -fsSL "${url}" | $_SUDO tar -xzf - -C "/usr/local/bin" --strip-components=1
