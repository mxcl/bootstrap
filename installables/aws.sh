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

if [ -n "${UPGRADE_STAGE_DIR:-}" ]; then
  tmpdir="$(mktemp -d "${UPGRADE_STAGE_DIR}/aws.XXXXXX")"
else
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir}"' EXIT
fi

outdir="${tmpdir}/out"
root_group="$(id -gn root)"
build_script_url="https://raw.githubusercontent.com/mxcl/bootstrap/refs/heads/main/build-aws.ts"
build_script="${tmpdir}/build-aws.ts"

deno_bin="${DENO_BIN:-/usr/local/bin/deno}"
if ! [ -x "${deno_bin}" ]; then
  if command -v deno >/dev/null 2>&1; then
    deno_bin="$(command -v deno)"
  else
    echo "deno not installed; run installables/deno.sh" >&2
    exit 1
  fi
fi

uv_bin="${UV_BIN:-/usr/local/bin/uv}"
if ! [ -x "${uv_bin}" ]; then
  if command -v uv >/dev/null 2>&1; then
    uv_bin="$(command -v uv)"
  else
    echo "uv not installed; run installables/uv.sh" >&2
    exit 1
  fi
fi
PATH="$(dirname "${uv_bin}"):${PATH}"
export PATH

curl -fsSL "${build_script_url}" -o "${build_script}"
/usr/bin/awk '
  /await Deno\.chmod\(linkPath, 0o755\);/ {
    print "    try {"
    print "      await Deno.chmod(linkPath, 0o755);"
    print "    } catch (err) {"
    print "      if (!(err instanceof Deno.errors.PermissionDenied)) {"
    print "        throw err;"
    print "      }"
    print "    }"
    next
  }
  { print }
' "${build_script}" >"${build_script}.patched"
mv "${build_script}.patched" "${build_script}"

"${deno_bin}" run -A \
  "${build_script}" \
  "${aws_version}" \
  --out "${outdir}"

# prune junk
rm -rf "${outdir}/share/awscli/bin/aws"*
rm -rf "${outdir}/share/awscli/bin/__pycache__"
rm -f "${outdir}/share/awscli/bin/distro"
rm -f "${outdir}/share/awscli/bin/docutils"
rm -f "${outdir}/share/awscli/bin/jp.py"
rm -f "${outdir}/share/awscli/bin/rst"*

$_SUDO install -d -m 755 /usr/local/bin /usr/local/share
$_SUDO rm -rf /usr/local/share/awscli
$_SUDO mv "${outdir}/share/awscli" /usr/local/share/awscli
$_SUDO chown -R "root:${root_group}" /usr/local/share/awscli
$_SUDO install -m 755 "${outdir}/bin/aws" /usr/local/bin/aws

if [ -n "${UPGRADE_STAGE_DIR:-}" ]; then
  $_SUDO rm -rf "${tmpdir}"
fi
