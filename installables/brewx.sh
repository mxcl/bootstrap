#!/bin/sh
set -eo pipefail

case "$(uname -s):$(uname -m)" in
  Darwin:arm64) target="darwin-aarch64";;
  Darwin:x86_64) target="darwin-x86_64";;
*)
  echo "unsupported platform" >&2
  exit 1;;
esac

version="$(curl -fsSL https://api.github.com/repos/mxcl/brewx/releases/latest | /usr/bin/jq -r '.tag_name')"

plain_version="${version#v}"
asset="brewx-${plain_version}-${target}.tar.gz"
url="https://github.com/mxcl/brewx/releases/download/${version}/${asset}"

curl -fsSL "${url}" | $_SUDO tar -xzf - -C /usr/local/bin
