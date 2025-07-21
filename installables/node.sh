#!/bin/sh
set -eo pipefail

os="$(uname -s)"
arch="$(uname -m)"

case "${os}:${arch}" in
  Darwin:arm64) target="darwin-arm64" ;;
  Darwin:x86_64) target="darwin-x64" ;;
  Linux:aarch64|Linux:arm64) target="linux-arm64" ;;
  Linux:x86_64) target="linux-x64" ;;
*)
  echo "Unsupported platform: ${os} ${arch}" >&2
  exit 1
  ;;
esac

node_version="${1:-}"
if [ -z "${node_version}" ]; then
  node_version="$(
    curl -fsSL https://nodejs.org/dist/index.json |
      /usr/bin/jq -r '.[0].version'
  )"
fi

if [ -z "${node_version}" ] || [ "${node_version}" = "null" ]; then
  echo "Unable to determine latest node version" >&2
  exit 1
fi

case "${node_version}" in
  v*) version="${node_version}" ;;
  *) version="v${node_version}" ;;
esac

asset="node-${version}-${target}.tar.gz"
url="https://nodejs.org/dist/${version}/${asset}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

curl -fsSL "${url}" -o "${tmpdir}/${asset}"
$_SUDO tar -C /usr/local --strip-components=1 -xzf "${tmpdir}/${asset}"
$_SUDO rm /usr/local/CHANGELOG.md /usr/local/README.md /usr/local/LICENSE
$_SUDO rm -rf /usr/local/doc
