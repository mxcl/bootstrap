#!/bin/sh
set -eo pipefail

DEFAULT_PYTHON_VERSION="3.12"
PYTHON_VERSIONS="3.10 3.11 3.12 3.13"
TARGET_DIR="/usr/local/bin"
_SUDO=sudo

umask 022

if [ ! -d "${TARGET_DIR}" ]; then
  mkdir -p "${TARGET_DIR}"
fi

if [ ! -w "${TARGET_DIR}" ]; then
  printf '%s\n' "setup: ${TARGET_DIR} not writable; try running with sudo" >&2
  exit 1
fi

if [ ! -d /opt/homebrew ]; then
  user="${SUDO_USER:-${USER:-$(id -un)}}"

  install -d -o root -g wheel -m 0755 /opt/homebrew
  for x in     bin etc include lib sbin opt Cellar Caskroom Frameworks     share/zsh/site-functions var/homebrew/linked var/log
  do
    mkdir -p "/opt/homebrew/${x}"
  done

  chown -R "${user}:admin" /opt/homebrew
  chmod -R ug=rwx,go=rx /opt/homebrew
  chmod go-w /opt/homebrew/share/zsh /opt/homebrew/share/zsh/site-functions

  chown -R "${user}:admin" /opt/homebrew
fi

write_stub() {
  target="$1"
  cat >"${target}"
  chmod 755 "${target}"
}

install_python() {
  for version in ${PYTHON_VERSIONS}; do
    target="${TARGET_DIR}/python${version}"
    write_stub "${target}" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/bash

set -eo pipefail

_python_version=
if ! _python_path="$(/usr/local/bin/uv python find --managed-python "$_python_version" 2>/dev/null)"; then
  /usr/local/bin/uv python install --managed-python "$_python_version"
  _python_path="$(/usr/local/bin/uv python find --managed-python "$_python_version")"
fi

exec "$_python_path" "$@"
__BOOTSTRAP_SCRIPT_EOF__
    sed -i '' "s|^_python_version=|_python_version=${version}|" "${target}"
  done

  rm -f "${TARGET_DIR}/python"
  ln -s "python3" "${TARGET_DIR}/python"

  rm -f "${TARGET_DIR}/python3"
  ln -s "python${DEFAULT_PYTHON_VERSION}" "${TARGET_DIR}/python3"
}

install_pip() {
  for version in ${PYTHON_VERSIONS}; do
    target="${TARGET_DIR}/pip${version}"
    write_stub "${target}" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh

set -eo pipefail

_python_version=

if ! _python_path="$(/usr/local/bin/uv python find --managed-python "$_python_version" 2>/dev/null)"; then
  /usr/local/bin/uv python install --managed-python "$_python_version"
  _python_path="$(/usr/local/bin/uv python find --managed-python "$_python_version")"
fi

exec "$(dirname "$_python_path")"/pip "$@"
__BOOTSTRAP_SCRIPT_EOF__
    sed -i '' "s|^_python_version=|_python_version=${version}|" "${target}"
  done

  rm -f "${TARGET_DIR}/pip"
  ln -s "pip3" "${TARGET_DIR}/pip"

  rm -f "${TARGET_DIR}/pip3"
  ln -s "pip${DEFAULT_PYTHON_VERSION}" "${TARGET_DIR}/pip3"
}

install_python
install_pip

write_stub "${TARGET_DIR}/upgrade" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh

if [ "$(id -u)" -eq 0 ]; then
  echo "panic: do not run as root" >&2
  exit 1
fi

if [ -x "/opt/homebrew/bin/brew" ]; then
  gum format "# Updating Homebrew"
  /opt/homebrew/bin/brew update
  /opt/homebrew/bin/brew upgrade
fi

gum format "# Updating Pythons"
/usr/local/bin/uv python upgrade

if [ -x "$HOME/.cargo/bin/cargo" ]; then
  gum format "# Updating Rust"
  "$HOME/.cargo/bin/rustup" update
fi

_SUDO=sudo


extract_version() {
  /usr/bin/awk '
    match($0, /v?[0-9]+([.][0-9]+)*/) {
      print substr($0, RSTART, RLENGTH)
      exit
    }
  '
}

sanitize_version() {
  printf '%s' "$1" | /usr/bin/sed -E 's/^[^0-9]*//; s/[^0-9.].*$//'
}

version_is_newer() {
  latest="$(sanitize_version "$1")"
  current="$(sanitize_version "$2")"

  if [ -z "${latest}" ] || [ -z "${current}" ]; then
    return 0
  fi

  /usr/bin/awk -v a="${latest}" -v b="${current}" '
    function splitver(v, arr,    i, n) {
      n = split(v, arr, ".");
      for (i = 1; i <= n; i++) if (arr[i] == "") arr[i] = 0;
      return n;
    }
    BEGIN {
      na = splitver(a, A);
      nb = splitver(b, B);
      n = (na > nb) ? na : nb;
      for (i = 1; i <= n; i++) {
        ai = (i <= na) ? A[i] : 0;
        bi = (i <= nb) ? B[i] : 0;
        if (ai + 0 > bi + 0) exit 0;
        if (ai + 0 < bi + 0) exit 1;
      }
      exit 2;
    }'

  case $? in
    0) return 0 ;;
    *) return 1 ;;
  esac
}

latest_tag() {
  repo="$1"
  tag="$(
    curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" |
      /usr/bin/jq -r '.tag_name'
  )"

  if [ -z "${tag}" ] || [ "${tag}" = "null" ]; then
    echo "Unable to determine latest release for ${repo}" >&2
    return 2
  fi

  printf '%s\n' "${tag}"
}

installed_version() {
  bin="$1"

  if [ -x "${bin}" ]; then
    "${bin}" --version 2>/dev/null | extract_version || true
  fi
}

outdated_aws() {



  bin="/usr/local/bin/aws"
  latest="$(
    curl -fsSL https://formulae.brew.sh/api/formula/awscli.json |
      /usr/bin/jq -r '.versions.stable'
  )"

  if [ -z "${latest}" ] || [ "${latest}" = "null" ]; then
    echo "Unable to determine latest awscli version" >&2
    return 2
  fi
  installed="$(installed_version "${bin}")"

  if [ -n "${installed}" ] && ! version_is_newer "${latest}" "${installed}"; then
    return 1
  fi

  printf '%s\n' "${latest}"
}

outdated_brewx() {



  repo="mxcl/brewx"
  bin="/usr/local/bin/brewx"

  latest="$(latest_tag "${repo}")"
  installed="$(installed_version "${bin}")"

  if [ -n "${installed}" ] && ! version_is_newer "${latest}" "${installed}"; then
    return 1
  fi

  printf '%s\n' "${latest}"
}

outdated_cargox() {



  repo="pkgxdev/cargox"
  bin="/usr/local/bin/cargox"

  latest="$(latest_tag "${repo}")"
  installed="$(installed_version "${bin}")"

  if [ -n "${installed}" ] && ! version_is_newer "${latest}" "${installed}"; then
    return 1
  fi

  printf '%s\n' "${latest}"
}

outdated_deno() {



  repo="denoland/deno"
  bin="/usr/local/bin/deno"

  yoink_bin="/usr/local/bin/yoink"
  if ! [ -x "${yoink_bin}" ]; then
    if command -v yoink >/dev/null 2>&1; then
      yoink_bin="$(command -v yoink)"
    else
      echo "yoink not installed; unable to check ${repo}" >&2
      return 2
    fi
  fi

  latest="$("${yoink_bin}" -jI "${repo}" | /usr/bin/jq -r '.tag')"

  if [ -z "${latest}" ] || [ "${latest}" = "null" ]; then
    echo "Unable to determine latest release for ${repo}" >&2
    return 2
  fi

  installed="$(installed_version "${bin}")"

  if [ -n "${installed}" ] && ! version_is_newer "${latest}" "${installed}"; then
    return 1
  fi

  printf '%s\n' "${latest}"
}

outdated_direnv() {



  repo="direnv/direnv"
  bin="/usr/local/bin/direnv"

  yoink_bin="/usr/local/bin/yoink"
  if ! [ -x "${yoink_bin}" ]; then
    if command -v yoink >/dev/null 2>&1; then
      yoink_bin="$(command -v yoink)"
    else
      echo "yoink not installed; unable to check ${repo}" >&2
      return 2
    fi
  fi

  latest="$("${yoink_bin}" -jI "${repo}" | /usr/bin/jq -r '.tag')"

  if [ -z "${latest}" ] || [ "${latest}" = "null" ]; then
    echo "Unable to determine latest release for ${repo}" >&2
    return 2
  fi

  installed="$(installed_version "${bin}")"

  if [ -n "${installed}" ] && ! version_is_newer "${latest}" "${installed}"; then
    return 1
  fi

  printf '%s\n' "${latest}"
}

outdated_node() {



  bin="/usr/local/bin/node"

  latest="$(
    curl -fsSL https://nodejs.org/dist/index.json |
      /usr/bin/jq -r '.[0].version'
  )"

  if [ -z "${latest}" ] || [ "${latest}" = "null" ]; then
    echo "Unable to determine latest node version" >&2
    return 2
  fi

  installed="$(installed_version "${bin}")"

  if [ -n "${installed}" ] && ! version_is_newer "${latest}" "${installed}"; then
    return 1
  fi

  printf '%s\n' "${latest}"
}

outdated_pkgx() {



  repo="pkgxdev/pkgx"
  bin="/usr/local/bin/pkgx"

  latest="$(latest_tag "${repo}")"
  installed="$(installed_version "${bin}")"

  if [ -n "${installed}" ] && ! version_is_newer "${latest}" "${installed}"; then
    return 1
  fi

  printf '%s\n' "${latest}"
}

outdated_uv() {



  repo="astral-sh/uv"
  bin="/usr/local/bin/uv"

  latest="$(latest_tag "${repo}")"
  installed="$(installed_version "${bin}")"

  if [ -n "${installed}" ] && ! version_is_newer "${latest}" "${installed}"; then
    return 1
  fi

  printf '%s\n' "${latest}"
}

outdated_yoink() {



  repo="mxcl/yoink"
  bin="/usr/local/bin/yoink"

  yoink_bin="/usr/local/bin/yoink"
  if ! [ -x "${yoink_bin}" ]; then
    if command -v yoink >/dev/null 2>&1; then
      yoink_bin="$(command -v yoink)"
    else
      latest="$(latest_tag "${repo}")"
    fi
  fi

  if [ -x "${yoink_bin}" ]; then
    latest="$("${yoink_bin}" -jI "${repo}" | /usr/bin/jq -r '.tag')"
  fi

  if [ -z "${latest:-}" ] || [ "${latest}" = "null" ]; then
    echo "Unable to determine latest release for ${repo}" >&2
    return 2
  fi
  installed="$(installed_version "${bin}")"

  if [ -n "${installed}" ] && ! version_is_newer "${latest}" "${installed}"; then
    return 1
  fi

  printf '%s\n' "${latest}"
}

install_yoink() {
  version="$1"
  set -eo pipefail

  curl -fsSL https://yoink.sh |
    $_SUDO sh -s -- -C /usr/local/bin mxcl/yoink
}

install_deno() {
  version="$1"
  set -eo pipefail

  yoink_bin="/usr/local/bin/yoink"
  if ! [ -x "${yoink_bin}" ]; then
    if command -v yoink >/dev/null 2>&1; then
      yoink_bin="$(command -v yoink)"
    else
      echo "yoink not installed; run installables/yoink.sh" >&2
      return 1
    fi
  fi

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir}"' EXIT

  downloaded="$(
    "${yoink_bin}" -C "${tmpdir}" denoland/deno |
      /usr/bin/head -n 1
  )"

  if [ -z "${downloaded}" ] || ! [ -f "${downloaded}" ]; then
    echo "deno binary not found after download" >&2
    return 1
  fi

  $_SUDO install -m 755 "${downloaded}" /usr/local/bin/deno
}

install_aws() {
  version="$1"
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
    return 1
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
}

install_brewx() {
  version="$1"
  set -eo pipefail

  yoink_bin="/usr/local/bin/yoink"
  if ! [ -x "${yoink_bin}" ]; then
    if command -v yoink >/dev/null 2>&1; then
      yoink_bin="$(command -v yoink)"
    else
      echo "yoink not installed; run installables/yoink.sh" >&2
      return 1
    fi
  fi

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir}"' EXIT

  paths="$("${yoink_bin}" -C "${tmpdir}" mxcl/brewx)"
  if [ -z "${paths}" ]; then
    echo "Unable to download brewx" >&2
    return 1
  fi

  for path in ${paths}; do
    if [ -z "${path}" ] || ! [ -f "${path}" ]; then
      echo "brewx binary not found after download" >&2
      return 1
    fi
    $_SUDO install -m 755 "${path}" "/usr/local/bin/$(basename "${path}")"
  done
}

install_cargox() {
  version="$1"
  set -eo pipefail

  yoink_bin="/usr/local/bin/yoink"
  if ! [ -x "${yoink_bin}" ]; then
    if command -v yoink >/dev/null 2>&1; then
      yoink_bin="$(command -v yoink)"
    else
      echo "yoink not installed; run installables/yoink.sh" >&2
      return 1
    fi
  fi

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir}"' EXIT

  paths="$("${yoink_bin}" -C "${tmpdir}" pkgxdev/cargox)"
  if [ -z "${paths}" ]; then
    echo "Unable to download cargox" >&2
    return 1
  fi

  for path in ${paths}; do
    if [ -z "${path}" ] || ! [ -f "${path}" ]; then
      echo "cargox binary not found after download" >&2
      return 1
    fi
    $_SUDO install -m 755 "${path}" "/usr/local/bin/$(basename "${path}")"
  done
}

install_direnv() {
  version="$1"
  set -eo pipefail

  yoink_bin="/usr/local/bin/yoink"
  if ! [ -x "${yoink_bin}" ]; then
    if command -v yoink >/dev/null 2>&1; then
      yoink_bin="$(command -v yoink)"
    else
      echo "yoink not installed; run installables/yoink.sh" >&2
      return 1
    fi
  fi

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir}"' EXIT

  downloaded="$(
    "${yoink_bin}" -C "${tmpdir}" direnv/direnv |
      /usr/bin/head -n 1
  )"

  if [ -z "${downloaded}" ] || ! [ -f "${downloaded}" ]; then
    echo "direnv binary not found after download" >&2
    return 1
  fi

  tmpbin="${tmpdir}/direnv"
  if [ "${downloaded}" != "${tmpbin}" ]; then
    mv "${downloaded}" "${tmpbin}"
  fi

  $_SUDO install -m 755 "${tmpbin}" /usr/local/bin/direnv
}

install_gh() {
  version="$1"
  set -eo pipefail

  yoink_bin="/usr/local/bin/yoink"
  if ! [ -x "${yoink_bin}" ]; then
    if command -v yoink >/dev/null 2>&1; then
      yoink_bin="$(command -v yoink)"
    else
      echo "yoink not installed; run installables/yoink.sh" >&2
      return 1
    fi
  fi

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir}"' EXIT

  paths="$("${yoink_bin}" -C "${tmpdir}" cli/cli)"
  if [ -z "${paths}" ]; then
    echo "Unable to download gh" >&2
    return 1
  fi

  for path in ${paths}; do
    if [ -z "${path}" ] || ! [ -f "${path}" ]; then
      echo "gh binary not found after download" >&2
      return 1
    fi
    $_SUDO install -m 755 "${path}" "/usr/local/bin/$(basename "${path}")"
  done
}

install_node() {
  version="$1"
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
    return 1
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
    return 1
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
}

install_pkgx() {
  version="$1"
  set -eo pipefail

  yoink_bin="/usr/local/bin/yoink"
  if ! [ -x "${yoink_bin}" ]; then
    if command -v yoink >/dev/null 2>&1; then
      yoink_bin="$(command -v yoink)"
    else
      echo "yoink not installed; run installables/yoink.sh" >&2
      return 1
    fi
  fi

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir}"' EXIT

  paths="$("${yoink_bin}" -C "${tmpdir}" pkgxdev/pkgx)"
  if [ -z "${paths}" ]; then
    echo "Unable to download pkgx" >&2
    return 1
  fi

  for path in ${paths}; do
    if [ -z "${path}" ] || ! [ -f "${path}" ]; then
      echo "pkgx binary not found after download" >&2
      return 1
    fi
    $_SUDO install -m 755 "${path}" "/usr/local/bin/$(basename "${path}")"
  done
}

install_uv() {
  version="$1"
  set -eo pipefail

  yoink_bin="/usr/local/bin/yoink"
  if ! [ -x "${yoink_bin}" ]; then
    if command -v yoink >/dev/null 2>&1; then
      yoink_bin="$(command -v yoink)"
    else
      echo "yoink not installed; run installables/yoink.sh" >&2
      return 1
    fi
  fi

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir}"' EXIT

  paths="$("${yoink_bin}" -C "${tmpdir}" astral-sh/uv)"
  if [ -z "${paths}" ]; then
    echo "Unable to download uv" >&2
    return 1
  fi

  for path in ${paths}; do
    if [ -z "${path}" ] || ! [ -f "${path}" ]; then
      echo "uv binary not found after download" >&2
      return 1
    fi
    $_SUDO install -m 755 "${path}" "/usr/local/bin/$(basename "${path}")"
  done
}

gum format "# Checking aws"

if version="$(outdated_aws)"; then
  install_aws "${version}"
fi

gum format "# Checking brewx"

if version="$(outdated_brewx)"; then
  install_brewx "${version}"
fi

gum format "# Checking cargox"

if version="$(outdated_cargox)"; then
  install_cargox "${version}"
fi

gum format "# Checking deno"

if version="$(outdated_deno)"; then
  install_deno "${version}"
fi

gum format "# Checking direnv"

if version="$(outdated_direnv)"; then
  install_direnv "${version}"
fi

gum format "# Checking node"

if version="$(outdated_node)"; then
  install_node "${version}"
fi

gum format "# Checking pkgx"

if version="$(outdated_pkgx)"; then
  install_pkgx "${version}"
fi

gum format "# Checking uv"

if version="$(outdated_uv)"; then
  install_uv "${version}"
fi

gum format "# Checking yoink"

if version="$(outdated_yoink)"; then
  install_yoink "${version}"
fi
__BOOTSTRAP_SCRIPT_EOF__

# installable: yoink.sh
set -eo pipefail

curl -fsSL https://yoink.sh |
  $_SUDO sh -s -- -C /usr/local/bin mxcl/yoink

# installable: deno.sh
set -eo pipefail

yoink_bin="/usr/local/bin/yoink"
if ! [ -x "${yoink_bin}" ]; then
  if command -v yoink >/dev/null 2>&1; then
    yoink_bin="$(command -v yoink)"
  else
    echo "yoink not installed; run installables/yoink.sh" >&2
    exit 1
  fi
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

downloaded="$(
  "${yoink_bin}" -C "${tmpdir}" denoland/deno |
    /usr/bin/head -n 1
)"

if [ -z "${downloaded}" ] || ! [ -f "${downloaded}" ]; then
  echo "deno binary not found after download" >&2
  exit 1
fi

$_SUDO install -m 755 "${downloaded}" /usr/local/bin/deno

# installable: aws.sh
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

# installable: brewx.sh
set -eo pipefail

yoink_bin="/usr/local/bin/yoink"
if ! [ -x "${yoink_bin}" ]; then
  if command -v yoink >/dev/null 2>&1; then
    yoink_bin="$(command -v yoink)"
  else
    echo "yoink not installed; run installables/yoink.sh" >&2
    exit 1
  fi
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

paths="$("${yoink_bin}" -C "${tmpdir}" mxcl/brewx)"
if [ -z "${paths}" ]; then
  echo "Unable to download brewx" >&2
  exit 1
fi

for path in ${paths}; do
  if [ -z "${path}" ] || ! [ -f "${path}" ]; then
    echo "brewx binary not found after download" >&2
    exit 1
  fi
  $_SUDO install -m 755 "${path}" "/usr/local/bin/$(basename "${path}")"
done

# installable: cargox.sh
set -eo pipefail

yoink_bin="/usr/local/bin/yoink"
if ! [ -x "${yoink_bin}" ]; then
  if command -v yoink >/dev/null 2>&1; then
    yoink_bin="$(command -v yoink)"
  else
    echo "yoink not installed; run installables/yoink.sh" >&2
    exit 1
  fi
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

paths="$("${yoink_bin}" -C "${tmpdir}" pkgxdev/cargox)"
if [ -z "${paths}" ]; then
  echo "Unable to download cargox" >&2
  exit 1
fi

for path in ${paths}; do
  if [ -z "${path}" ] || ! [ -f "${path}" ]; then
    echo "cargox binary not found after download" >&2
    exit 1
  fi
  $_SUDO install -m 755 "${path}" "/usr/local/bin/$(basename "${path}")"
done

# installable: direnv.sh
set -eo pipefail

yoink_bin="/usr/local/bin/yoink"
if ! [ -x "${yoink_bin}" ]; then
  if command -v yoink >/dev/null 2>&1; then
    yoink_bin="$(command -v yoink)"
  else
    echo "yoink not installed; run installables/yoink.sh" >&2
    exit 1
  fi
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

downloaded="$(
  "${yoink_bin}" -C "${tmpdir}" direnv/direnv |
    /usr/bin/head -n 1
)"

if [ -z "${downloaded}" ] || ! [ -f "${downloaded}" ]; then
  echo "direnv binary not found after download" >&2
  exit 1
fi

tmpbin="${tmpdir}/direnv"
if [ "${downloaded}" != "${tmpbin}" ]; then
  mv "${downloaded}" "${tmpbin}"
fi

$_SUDO install -m 755 "${tmpbin}" /usr/local/bin/direnv

# installable: gh.sh
set -eo pipefail

yoink_bin="/usr/local/bin/yoink"
if ! [ -x "${yoink_bin}" ]; then
  if command -v yoink >/dev/null 2>&1; then
    yoink_bin="$(command -v yoink)"
  else
    echo "yoink not installed; run installables/yoink.sh" >&2
    exit 1
  fi
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

paths="$("${yoink_bin}" -C "${tmpdir}" cli/cli)"
if [ -z "${paths}" ]; then
  echo "Unable to download gh" >&2
  exit 1
fi

for path in ${paths}; do
  if [ -z "${path}" ] || ! [ -f "${path}" ]; then
    echo "gh binary not found after download" >&2
    exit 1
  fi
  $_SUDO install -m 755 "${path}" "/usr/local/bin/$(basename "${path}")"
done

# installable: node.sh
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

# installable: pkgx.sh
set -eo pipefail

yoink_bin="/usr/local/bin/yoink"
if ! [ -x "${yoink_bin}" ]; then
  if command -v yoink >/dev/null 2>&1; then
    yoink_bin="$(command -v yoink)"
  else
    echo "yoink not installed; run installables/yoink.sh" >&2
    exit 1
  fi
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

paths="$("${yoink_bin}" -C "${tmpdir}" pkgxdev/pkgx)"
if [ -z "${paths}" ]; then
  echo "Unable to download pkgx" >&2
  exit 1
fi

for path in ${paths}; do
  if [ -z "${path}" ] || ! [ -f "${path}" ]; then
    echo "pkgx binary not found after download" >&2
    exit 1
  fi
  $_SUDO install -m 755 "${path}" "/usr/local/bin/$(basename "${path}")"
done

# installable: uv.sh
set -eo pipefail

yoink_bin="/usr/local/bin/yoink"
if ! [ -x "${yoink_bin}" ]; then
  if command -v yoink >/dev/null 2>&1; then
    yoink_bin="$(command -v yoink)"
  else
    echo "yoink not installed; run installables/yoink.sh" >&2
    exit 1
  fi
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

paths="$("${yoink_bin}" -C "${tmpdir}" astral-sh/uv)"
if [ -z "${paths}" ]; then
  echo "Unable to download uv" >&2
  exit 1
fi

for path in ${paths}; do
  if [ -z "${path}" ] || ! [ -f "${path}" ]; then
    echo "uv binary not found after download" >&2
    exit 1
  fi
  $_SUDO install -m 755 "${path}" "/usr/local/bin/$(basename "${path}")"
done

write_stub "${TARGET_DIR}/brew" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh

set -eo pipefail

if [ ! -x /opt/homebrew/bin/brew ]; then
  if [ "$(id -u)" -eq 0 ]; then
    printf '%s\n' "brew: refusing to bootstrap /opt/homebrew as root" >&2
    exit 1
  fi

  cd /opt/homebrew
  git init -q
  git config remote.origin.url "https://github.com/Homebrew/brew"
  git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
  git config --bool fetch.prune true
  git config --bool core.autocrlf false
  git config --bool core.symlinks true

  git fetch --force --tags origin
  git remote set-head origin --auto >/dev/null || true

  latest_tag="$(git tag --list --sort='-version:refname' | head -n1)"
  git checkout -q -f -B stable "$latest_tag"

  /opt/homebrew/bin/brew update --force
fi

exec /opt/homebrew/bin/brew "$@"
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/cargo" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh

set -eo pipefail

CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"

if [ ! -f "$CARGO_HOME/bin/rustup" ]; then
  echo "a \`rustup\` toolchain has not been installed for this user" >&2
  echo "run: \`rustup init\`" >&2
  exit 3
fi

#TODO path might be different
source "$CARGO_HOME/env"

exec "$CARGO_HOME/bin/cargo" "$@"
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/cmake" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/usr/bin/env -S brewx -! cmake
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/code" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh

if ! [ -d /Applications/Visual\ Studio\ Code.app ]; then
  brew install --cask visual-studio-code
fi

exec /Applications/Visual\ Studio\ Code.app/Contents/Resources/app/bin/code "$@"
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/code_wait" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh

if ! [ -d /Applications/Visual\ Studio\ Code.app ]; then
  brew install --cask visual-studio-code
fi

exec /Applications/Visual\ Studio\ Code.app/Contents/Resources/app/bin/code --wait "$@"
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/codex" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh

if [ ! -d /Applications/Fork.app ]; then
  /usr/local/bin/brew install --cask codex
fi

exec /opt/homebrew/bin/codex "$@"
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/cwebp" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/usr/bin/env -S brewx -! cwebp
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/fork" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh

if [ ! -d /Applications/Fork.app ]; then
  /usr/local/bin/brew install --cask fork
fi

exec /Applications/Fork.app/Contents/Resources/fork_cli "$@"
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/git" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh

set -eo pipefail

if [ -x /Library/Developer/CommandLineTools/usr/bin/git ]; then
  exec /Library/Developer/CommandLineTools/usr/bin/git "$@"
fi

exec /usr/local/bin/brewx git "$@"
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/gum" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/usr/bin/env -S brewx -! gum
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/hyperfine" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh
exec /usr/local/bin/cargox hyperfine "$@"
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/jq" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh

set -eo pipefail

if [ -x /Library/Developer/CommandLineTools/usr/bin/jq ]; then
  exec /Library/Developer/CommandLineTools/usr/bin/jq "$@"
fi

exec /usr/local/bin/brewx jq "$@"
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/magick" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/usr/bin/env -S brewx -! magick
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/ollama" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh

if [ ! -d /Applications/Ollama.app ]; then
  /usr/local/bin/brew install --cask ollama
fi

exec /Applications/Ollama.app/Contents/Resources/ollama "$@"
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/pip3.9" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh

set -eo pipefail

if [ -x /Library/Developer/CommandLineTools/usr/bin/pip3 ]; then
  exec /Library/Developer/CommandLineTools/usr/bin/pip3 "$@"
fi

if ! _python_path="$(/usr/local/bin/uv python find --managed-python 3.9 2>/dev/null)"; then
  /usr/local/bin/uv python install --managed-python 3.9
  _python_path="$(/usr/local/bin/uv python find --managed-python 3.9)"
fi

exec "$(dirname "$_python_path")"/pip3 "$@"
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/python3.9" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh

set -eo pipefail

if [ -x /Library/Developer/CommandLineTools/usr/bin/python3 ]; then
  exec /Library/Developer/CommandLineTools/usr/bin/python3 "$@"
fi

if ! _python_path="$(/usr/local/bin/uv python find --managed-python 3.9 2>/dev/null)"; then
  /usr/local/bin/uv python install --managed-python 3.9
  _python_path="$(/usr/local/bin/uv python find --managed-python 3.9)"
fi

exec "$_python_path" "$@"
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/rustc" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh

set -eo pipefail

CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"

if [ ! -f "$CARGO_HOME/bin/rustup" ]; then
  echo "a \`rustup\` toolchain has not been installed" >&2
  echo "run: \`rustup init\`" >&2
  exit 3
fi

#TODO path might be different
source "$CARGO_HOME/env"

exec "$CARGO_HOME/bin/rustc" "$@"
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/rustup" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh

set -eo pipefail

CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"

if [ ! -f "$CARGO_HOME/bin/rustup" -a "$1" = init ]; then
  # prevent rustup-init from warning that rust is already installed when it is just us
  export RUSTUP_INIT_SKIP_PATH_CHECK=yes

  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --no-modify-path
  exit $?
elif [ ! -f "$CARGO_HOME/bin/rustup" ]; then
  echo "a \`rustup\` toolchain has not been installed" >&2
  echo "run: \`rustup init\`" >&2
  exit 3
fi

exec "$CARGO_HOME/bin/rustup" "$@"
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/xc" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/usr/bin/env -S brewx -! xc
__BOOTSTRAP_SCRIPT_EOF__
