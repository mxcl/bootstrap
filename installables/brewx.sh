#!/bin/sh
set -eo pipefail

case "$(uname -s):$(uname -m)" in
  Darwin:arm64)
    target_label="darwin-aarch64"
    asset_re='brewx-.*(darwin|macos|apple-darwin).*(aarch64|arm64)\.tar\.gz$'
    ;;
  Darwin:x86_64)
    target_label="darwin-x86_64"
    asset_re='brewx-.*(darwin|macos|apple-darwin).*(x86_64|amd64)\.tar\.gz$'
    ;;
*)
  echo "unsupported platform" >&2
  exit 1;;
esac

version="$(
  curl -fsSL https://api.github.com/repos/mxcl/brewx/releases/latest |
    /usr/bin/jq -r '.tag_name'
)"

release_json="$(
  curl -fsSL "https://api.github.com/repos/mxcl/brewx/releases/tags/${version}" ||
    curl -fsSL https://api.github.com/repos/mxcl/brewx/releases/latest
)"

url="$(
  printf '%s' "${release_json}" |
    /usr/bin/jq -r --arg re "${asset_re}" '
      .assets | map(select(.name | test($re))) |
      .[0].browser_download_url // empty
    '
)"

if [ -z "${url}" ]; then
  echo "Unable to find brewx asset for ${version} (${target_label})" >&2
  exit 1
fi

curl -fsSL "${url}" | $_SUDO tar -xzf - -C /usr/local/bin
