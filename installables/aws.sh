#!/bin/sh
set -eo pipefail

aws_version="${1:-}"
if [ -z "${aws_version}" ]; then
  aws_version="$(
    curl -fsSL https://formulae.brew.sh/api/formula/awscli.json |
      /usr/bin/jq -r '.versions.stable'
  )"
fi

if [ -z "${aws_version}" ] || [ "${aws_version}" = "null" ]; then
  echo "Unable to determine latest awscli version" >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

outdir="${tmpdir}/out"

/usr/local/bin/deno run -A \
  https://raw.githubusercontent.com/mxcl/bootstrap/refs/heads/main/build-aws.ts \
  "${aws_version}" \
  --out "${outdir}"

# prune junk
rm -rf ${outdir}/share/awscli/bin/aws*
rm -rf ${outdir}/share/awscli/bin/__pycache__
rm ${outdir}/share/awscli/bin/distro
rm ${outdir}/share/awscli/bin/docutils
rm ${outdir}/share/awscli/bin/jp.py
rm ${outdir}/share/awscli/bin/rst*

$_SUDO install -d -m 755 /usr/local/bin /usr/local/share
$_SUDO rm -rf /usr/local/share/awscli
$_SUDO mv "${outdir}/share/awscli" /usr/local/share/awscli
$_SUDO install -m 755 "${outdir}/bin/aws" /usr/local/bin/aws
