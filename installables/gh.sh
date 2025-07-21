#!/bin/sh
set -eo pipefail

os="$(uname -s)"
arch="$(uname -m)"

case "${os}:${arch}" in
  Darwin:arm64) target_os="macOS"; target_arch="arm64"; asset_ext="zip" ;;
  Darwin:x86_64) target_os="macOS"; target_arch="amd64"; asset_ext="zip" ;;
  Linux:aarch64|Linux:arm64) target_os="linux"; target_arch="arm64"; asset_ext="tar.gz" ;;
  Linux:x86_64) target_os="linux"; target_arch="amd64"; asset_ext="tar.gz" ;;
*)
  echo "Unsupported platform: ${os} ${arch}" >&2
  exit 1
  ;;
esac

gh_version="${1:-}"
if [ -z "${gh_version}" ]; then
  gh_version="$(
    curl -fsSL https://api.github.com/repos/cli/cli/releases/latest |
      /usr/bin/jq -r '.tag_name'
  )"
fi

if [ -z "${gh_version}" ] || [ "${gh_version}" = "null" ]; then
  echo "Unable to determine latest gh version" >&2
  exit 1
fi

case "${gh_version}" in
  v*) version="${gh_version}" ;;
  *) version="v${gh_version}" ;;
esac

version_trim="${version#v}"
asset="gh_${version_trim}_${target_os}_${target_arch}.${asset_ext}"
url="https://github.com/cli/cli/releases/download/${version}/${asset}"
checksums="gh_${version_trim}_checksums.txt"
checksums_url="https://github.com/cli/cli/releases/download/${version}/${checksums}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

curl -fsSL "${url}" -o "${tmpdir}/${asset}"
curl -fsSL "${checksums_url}" -o "${tmpdir}/${checksums}"

expected_sha="$(
  /usr/bin/awk -v asset="${asset}" '$2 == asset { print $1 }' "${tmpdir}/${checksums}"
)"
if [ -z "${expected_sha}" ]; then
  echo "Unable to find checksum for ${asset}" >&2
  exit 1
fi

if command -v shasum >/dev/null 2>&1; then
  actual_sha="$(shasum -a 256 "${tmpdir}/${asset}" | /usr/bin/awk '{print $1}')"
elif command -v sha256sum >/dev/null 2>&1; then
  actual_sha="$(sha256sum "${tmpdir}/${asset}" | /usr/bin/awk '{print $1}')"
else
  actual_sha="$(openssl dgst -sha256 "${tmpdir}/${asset}" | /usr/bin/awk '{print $2}')"
fi

if [ "${actual_sha}" != "${expected_sha}" ]; then
  echo "Checksum mismatch for ${asset}" >&2
  exit 1
fi

outdir="${tmpdir}/out"
mkdir -p "${outdir}"

case "${asset_ext}" in
  zip)
    unzip -q "${tmpdir}/${asset}" -d "${outdir}"
    ;;
  tar.gz)
    tar -C "${outdir}" -xzf "${tmpdir}/${asset}"
    ;;
esac

bin_path="${outdir}/gh_${version_trim}_${target_os}_${target_arch}/bin/gh"
if ! [ -x "${bin_path}" ]; then
  echo "gh binary not found in archive" >&2
  exit 1
fi

$_SUDO install -m 755 "${bin_path}" /usr/local/bin/gh
