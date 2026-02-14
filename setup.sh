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

write_stub "${TARGET_DIR}/outdated" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh
set -e

if [ "$(id -u)" -eq 0 ]; then
  echo "panic: do not run as root" >&2
  exit 1
fi

GUM_BIN="$(command -v gum 2>/dev/null || true)"
if [ -n "${GUM_BIN}" ] && ! "${GUM_BIN}" --version >/dev/null 2>&1; then
  GUM_BIN=
fi
OUTDATED_SELF="$0"

case "${OUTDATED_SELF}" in
  */*)
    ;;
  *)
    resolved_self="$(command -v "${OUTDATED_SELF}" 2>/dev/null || true)"
    if [ -n "${resolved_self}" ]; then
      OUTDATED_SELF="${resolved_self}"
    fi
    ;;
esac

if ! [ -x "${OUTDATED_SELF}" ]; then
  resolved_self="$(command -v outdated 2>/dev/null || true)"
  if [ -n "${resolved_self}" ]; then
    OUTDATED_SELF="${resolved_self}"
  fi
fi

gum() {
  if [ -n "${GUM_BIN}" ]; then
    "${GUM_BIN}" "$@"
  fi
}

is_internal_command() {
  case "$1" in
    uv_python_upgrade_available|rustup_upgrade_available|outdated_*|install_*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_known_install_target() {
  return 1
}

run_internal() {
  target="${1:-}"
  if [ -z "${target}" ]; then
    echo "panic: missing internal target" >&2
    exit 1
  fi
  shift

  if ! is_internal_command "${target}"; then
    echo "panic: unknown internal target: ${target}" >&2
    exit 1
  fi

  case "${target}" in
    outdated_*|install_*)
      OUTDATED_BOOTSTRAP_ONLY=1
      run_outdated >/dev/null
      ;;
  esac

  "${target}" "$@"
}

run_step() {
  title="$1"
  shift
  command_name="$1"
  shift

  if [ -n "${GUM_BIN}" ]; then
    if is_internal_command "${command_name}"; then
      gum spin --title "${title}" -- "${OUTDATED_SELF}" --internal-run \
        "${command_name}" "$@"
    else
      gum spin --title "${title}" -- "${command_name}" "$@"
    fi
  else
    printf '# %s\n' "${title}" >&2
    "${command_name}" "$@"
  fi
}

run_step_capture() {
  title="$1"
  shift
  command_name="$1"
  shift

  if [ -n "${GUM_BIN}" ]; then
    if is_internal_command "${command_name}"; then
      gum spin --show-output --title "${title}" -- "${OUTDATED_SELF}" \
        --internal-run "${command_name}" "$@"
    else
      gum spin --show-output --title "${title}" -- "${command_name}" "$@"
    fi
  else
    printf '# %s\n' "${title}" >&2
    "${command_name}" "$@"
  fi
}

shell_quote() {
  escaped="$(printf '%s' "$1" | /usr/bin/sed "s/'/'\\\\''/g")"
  printf "'%s'" "${escaped}"
}

queue_arg() {
  quoted="$(shell_quote "$1")"
  APPLY_ARGS="${APPLY_ARGS} ${quoted}"
  PLAN_HAS_ACTION=1
}

queue_brew_upgrade() {
  queue_arg "--brew"
}

queue_uv_python_upgrade() {
  queue_arg "--uv-python"
}

queue_rustup_upgrade() {
  queue_arg "--rustup"
}

queue_install() {
  name="$1"
  version="$2"
  if [ -z "${name}" ] || [ -z "${version}" ]; then
    return 0
  fi

  queue_arg "--install"
  queue_arg "${name}=${version}"
}

append_install_spec() {
  if [ -z "${REORDERED_INSTALL_QUEUE}" ]; then
    REORDERED_INSTALL_QUEUE="${1}"
  else
    REORDERED_INSTALL_QUEUE="${REORDERED_INSTALL_QUEUE}
${1}"
  fi
}

reorder_install_queue() {
  if [ -z "${INSTALL_QUEUE}" ]; then
    return 0
  fi

  REORDERED_INSTALL_QUEUE=""

  while IFS= read -r spec; do
    if [ -z "${spec}" ]; then
      continue
    fi
    name="${spec%%=*}"
    if [ "${name}" = "yoink" ]; then
      append_install_spec "${spec}"
    fi
  done <<EOF
${INSTALL_QUEUE}
EOF

  while IFS= read -r spec; do
    if [ -z "${spec}" ]; then
      continue
    fi
    name="${spec%%=*}"
    if [ "${name}" = "deno" ]; then
      append_install_spec "${spec}"
    fi
  done <<EOF
${INSTALL_QUEUE}
EOF

  while IFS= read -r spec; do
    if [ -z "${spec}" ]; then
      continue
    fi
    name="${spec%%=*}"
    if [ "${name}" = "uv" ]; then
      append_install_spec "${spec}"
    fi
  done <<EOF
${INSTALL_QUEUE}
EOF

  while IFS= read -r spec; do
    if [ -z "${spec}" ]; then
      continue
    fi
    name="${spec%%=*}"
    if [ "${name}" = "aws" ]; then
      append_install_spec "${spec}"
    fi
  done <<EOF
${INSTALL_QUEUE}
EOF

  while IFS= read -r spec; do
    if [ -z "${spec}" ]; then
      continue
    fi
    name="${spec%%=*}"
    case "${name}" in
      yoink|deno|uv|aws)
        continue
        ;;
    esac
    append_install_spec "${spec}"
  done <<EOF
${INSTALL_QUEUE}
EOF

  INSTALL_QUEUE="${REORDERED_INSTALL_QUEUE}"
}

emit_plan() {
  if [ "${PLAN_HAS_ACTION}" -eq 0 ]; then
    return 0
  fi

  printf '#!/bin/sh\n'
  printf 'set -e\n'
  printf '\n'
  printf 'exec /usr/local/bin/outdated --apply%s\n' "${APPLY_ARGS}"
}

begin_root_script() {
  ROOT_SCRIPT="${UPGRADE_STAGE_DIR}/root.sh"
  cat >"${ROOT_SCRIPT}" <<'EOF'
#!/bin/sh
set -e

apply_root_updates() {
EOF
  ROOT_COMMANDS_QUEUED=0
}

emit_root() {
  ROOT_COMMANDS_QUEUED=1

  sep=""
  printf '  ' >>"${ROOT_SCRIPT}"
  for arg in "$@"; do
    escaped="$(printf '%s' "${arg}" | /usr/bin/sed "s/'/'\\\\''/g")"
    printf "%s'%s'" "${sep}" "${escaped}" >>"${ROOT_SCRIPT}"
    sep=" "
  done
  printf '\n' >>"${ROOT_SCRIPT}"
}

apply_root_commands() {
  cat >>"${ROOT_SCRIPT}" <<'EOF'
}

apply_root_updates "$@"
EOF

  chmod 700 "${ROOT_SCRIPT}"

  if [ "${ROOT_COMMANDS_QUEUED}" -eq 0 ]; then
    return 0
  fi

  run_step "Applying privileged updates" sudo "${ROOT_SCRIPT}"
}

max_version() {
  best=""
  while IFS= read -r candidate; do
    if [ -z "${candidate}" ]; then
      continue
    fi
    if [ -z "${best}" ] || template_version_is_newer "${candidate}" "${best}"; then
      best="${candidate}"
    fi
  done
  printf '%s\n' "${best}"
}

template_sanitize_version() {
  printf '%s' "$1" | /usr/bin/sed -E 's/^[^0-9]*//; s/[^0-9.].*$//'
}

template_version_is_newer() {
  latest="$(template_sanitize_version "$1")"
  current="$(template_sanitize_version "$2")"

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

uv_python_upgrade_available() {
  if ! [ -x "/usr/local/bin/uv" ]; then
    return 1
  fi

  if ! command -v /usr/bin/jq >/dev/null 2>&1; then
    return 0
  fi

  installed_json="$(
    /usr/local/bin/uv python list --only-installed --output-format json \
      2>/dev/null || true
  )"
  if [ -z "${installed_json}" ] || [ "${installed_json}" = "[]" ]; then
    return 1
  fi

  minors="$(
    printf '%s' "${installed_json}" |
      /usr/bin/jq -r '
        .[] |
        select(.implementation == "cpython") |
        select(.path != null and (.path | contains("/.local/share/uv/python/"))) |
        "\(.version_parts.major).\(.version_parts.minor)"
      ' 2>/dev/null |
      /usr/bin/sort -u
  )"

  if [ -z "${minors}" ]; then
    return 1
  fi

  for minor in ${minors}; do
    installed_versions="$(
      printf '%s' "${installed_json}" |
        /usr/bin/jq -r --arg minor "${minor}" '
          .[] |
          select(.implementation == "cpython") |
          select(.path != null and (.path | contains("/.local/share/uv/python/"))) |
          select(
            ((.version_parts.major | tostring) + "." +
            (.version_parts.minor | tostring)) == $minor
          ) |
          .version
        ' 2>/dev/null
    )"
    current="$(printf '%s\n' "${installed_versions}" | max_version)"
    if [ -z "${current}" ]; then
      continue
    fi

    available_json="$(
      /usr/local/bin/uv python list "${minor}" --only-downloads --output-format \
        json 2>/dev/null || true
    )"
    if [ -z "${available_json}" ] || [ "${available_json}" = "[]" ]; then
      continue
    fi

    available_versions="$(
      printf '%s' "${available_json}" |
        /usr/bin/jq -r --arg minor "${minor}" '
          .[] |
          select(.implementation == "cpython") |
          select(
            ((.version_parts.major | tostring) + "." +
            (.version_parts.minor | tostring)) == $minor
          ) |
          .version
        ' 2>/dev/null
    )"
    latest="$(printf '%s\n' "${available_versions}" | max_version)"

    if [ -n "${latest}" ] && template_version_is_newer "${latest}" "${current}"; then
      return 0
    fi
  done

  return 1
}

rustup_upgrade_available() {
  if ! [ -x "$HOME/.cargo/bin/rustup" ]; then
    return 1
  fi

  if "$HOME/.cargo/bin/rustup" check 2>/dev/null |
    /usr/bin/grep -q "Update available"
  then
    return 0
  fi

  return 1
}

run_apply() {
  APPLY_BREW=0
  APPLY_UV_PYTHON=0
  APPLY_RUSTUP=0
  INSTALL_QUEUE=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --brew)
        APPLY_BREW=1
        ;;
      --uv-python)
        APPLY_UV_PYTHON=1
        ;;
      --rustup)
        APPLY_RUSTUP=1
        ;;
      --install)
        shift
        if [ $# -eq 0 ]; then
          echo "panic: --install requires NAME=VERSION" >&2
          exit 1
        fi
        if [ -z "${INSTALL_QUEUE}" ]; then
          INSTALL_QUEUE="$1"
        else
          INSTALL_QUEUE="${INSTALL_QUEUE}
$1"
        fi
        ;;
      *)
        echo "panic: unknown apply argument: $1" >&2
        exit 1
        ;;
    esac
    shift
  done

  UPGRADE_STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/upgrade.XXXXXX")"
  if ! [ -d "${UPGRADE_STAGE_DIR}" ]; then
    echo "panic: failed to create staging directory" >&2
    exit 1
  fi
  trap 'rm -rf "${UPGRADE_STAGE_DIR}"' EXIT

  run_step "Staging in ${UPGRADE_STAGE_DIR}" true
  begin_root_script
  _SUDO=emit_root

  if [ "${APPLY_BREW}" -eq 1 ] && [ -x "/opt/homebrew/bin/brew" ]; then
    run_step "Updating Homebrew" /opt/homebrew/bin/brew upgrade
  fi

  if [ "${APPLY_UV_PYTHON}" -eq 1 ] && [ -x "/usr/local/bin/uv" ]; then
    run_step "Updating Pythons" /usr/local/bin/uv python upgrade
  fi

  if [ "${APPLY_RUSTUP}" -eq 1 ] && [ -x "$HOME/.cargo/bin/rustup" ]; then
    run_step "Updating Rust" "$HOME/.cargo/bin/rustup" update
  fi

  if [ -n "${INSTALL_QUEUE}" ]; then
    reorder_install_queue

    while IFS= read -r spec; do
      if [ -z "${spec}" ]; then
        continue
      fi

      name="${spec%%=*}"
      version="${spec#*=}"
      if [ -z "${name}" ] || [ "${name}" = "${spec}" ] || [ -z "${version}" ]; then
        echo "panic: invalid install spec: ${spec}" >&2
        exit 1
      fi

      case "${name}" in
        *[!A-Za-z0-9_]*)
          echo "panic: invalid install target: ${name}" >&2
          exit 1
          ;;
      esac

      if ! is_known_install_target "${name}"; then
        echo "panic: unknown install target: ${name}" >&2
        exit 1
      fi

      install_func="install_${name}"
      run_step "Updating ${name}" "${install_func}" "${version}"
    done <<EOF
${INSTALL_QUEUE}
EOF
  fi

  apply_root_commands
}

run_outdated() {
  APPLY_ARGS=""
  PLAN_HAS_ACTION=0

  if [ "${OUTDATED_BOOTSTRAP_ONLY:-0}" -ne 1 ]; then
    if [ -x "/opt/homebrew/bin/brew" ]; then
      if run_step "Checking Homebrew" /bin/sh -c \
        '[ -n "$(/opt/homebrew/bin/brew outdated 2>/dev/null)" ]'
      then
        queue_brew_upgrade
      fi
    fi

    if [ -x "/usr/local/bin/uv" ]; then
      if run_step "Checking Pythons" uv_python_upgrade_available; then
        queue_uv_python_upgrade
      fi
    fi

    if [ -x "$HOME/.cargo/bin/rustup" ]; then
      if run_step "Checking Rust" rustup_upgrade_available; then
        queue_rustup_upgrade
      fi
    fi
  fi


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
      /usr/bin/awk '
        found == 0 &&
        match($0, /"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"/) {
          value = substr($0, RSTART, RLENGTH)
          sub(/^.*:[[:space:]]*"/, "", value)
          sub(/"$/, "", value)
          print value
          found = 1
        }'
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

outdated_yoink() {



  repo="mxcl/yoink"
  bin="/usr/local/bin/yoink"

  latest="$(latest_tag "${repo}")"

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

outdated_aws() {



  bin="/usr/local/bin/aws"
  latest="$(
    curl -fsSL https://formulae.brew.sh/api/formula/awscli.json |
      /usr/bin/awk '
        found == 0 &&
        match($0, /"stable"[[:space:]]*:[[:space:]]*"[^"]+"/) {
          value = substr($0, RSTART, RLENGTH)
          sub(/^.*:[[:space:]]*"/, "", value)
          sub(/"$/, "", value)
          print value
          found = 1
        }'
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

  latest="$(latest_tag "${repo}")"

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

  latest="$(latest_tag "${repo}")"

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
      /usr/bin/awk '
        found == 0 &&
        match($0, /"version"[[:space:]]*:[[:space:]]*"[^"]+"/) {
          value = substr($0, RSTART, RLENGTH)
          sub(/^.*:[[:space:]]*"/, "", value)
          sub(/"$/, "", value)
          print value
          found = 1
        }'
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

install_yoink() {
  version="$1"
  set -eo pipefail

  if [ -n "${UPGRADE_STAGE_DIR:-}" ]; then
    tmpdir="$(mktemp -d "${UPGRADE_STAGE_DIR}/yoink.XXXXXX")"
    install_script="${tmpdir}/install.sh"
    curl -fsSL https://yoink.sh -o "${install_script}"
    staged_bin_dir="${UPGRADE_STAGE_DIR}/bin"
    mkdir -p "${staged_bin_dir}"
    yoink_path="$(
      sh "${install_script}" -C "${staged_bin_dir}" mxcl/yoink |
        /usr/bin/head -n 1
    )"
    if [ -z "${yoink_path}" ] || ! [ -x "${yoink_path}" ]; then
      echo "yoink binary not found after download" >&2
      return 1
    fi
    YOINK_BIN="${yoink_path}"
    export YOINK_BIN
    $_SUDO install -m 755 "${yoink_path}" /usr/local/bin/yoink
    $_SUDO rm -rf "${tmpdir}"
  else
    curl -fsSL https://yoink.sh |
      $_SUDO sh -s -- -C /usr/local/bin mxcl/yoink
  fi
}

install_deno() {
  version="$1"
  set -eo pipefail

  yoink_bin="${YOINK_BIN:-/usr/local/bin/yoink}"
  if ! [ -x "${yoink_bin}" ]; then
    if command -v yoink >/dev/null 2>&1; then
      yoink_bin="$(command -v yoink)"
    else
      echo "yoink not installed; run installables/yoink.sh" >&2
      return 1
    fi
  fi

  if [ -n "${UPGRADE_STAGE_DIR:-}" ]; then
    tmpdir="$(mktemp -d "${UPGRADE_STAGE_DIR}/deno.XXXXXX")"
  else
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "${tmpdir}"' EXIT
  fi

  downloaded="$(
    "${yoink_bin}" -C "${tmpdir}" denoland/deno |
      /usr/bin/head -n 1
  )"

  if [ -z "${downloaded}" ] || ! [ -f "${downloaded}" ]; then
    echo "deno binary not found after download" >&2
    return 1
  fi

  if [ -n "${UPGRADE_STAGE_DIR:-}" ]; then
    staged_bin_dir="${UPGRADE_STAGE_DIR}/bin"
    mkdir -p "${staged_bin_dir}"
    staged_deno="${staged_bin_dir}/deno"
    cp "${downloaded}" "${staged_deno}"
    chmod 755 "${staged_deno}"
    DENO_BIN="${staged_deno}"
    export DENO_BIN
  fi

  $_SUDO install -m 755 "${downloaded}" /usr/local/bin/deno

  if [ -n "${UPGRADE_STAGE_DIR:-}" ]; then
    $_SUDO rm -rf "${tmpdir}"
  fi
}

install_uv() {
  version="$1"
  set -eo pipefail

  yoink_bin="${YOINK_BIN:-/usr/local/bin/yoink}"
  if ! [ -x "${yoink_bin}" ]; then
    if command -v yoink >/dev/null 2>&1; then
      yoink_bin="$(command -v yoink)"
    else
      echo "yoink not installed; run installables/yoink.sh" >&2
      return 1
    fi
  fi

  if [ -n "${UPGRADE_STAGE_DIR:-}" ]; then
    tmpdir="$(mktemp -d "${UPGRADE_STAGE_DIR}/uv.XXXXXX")"
  else
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "${tmpdir}"' EXIT
  fi

  paths="$("${yoink_bin}" -C "${tmpdir}" astral-sh/uv)"
  if [ -z "${paths}" ]; then
    echo "Unable to download uv" >&2
    return 1
  fi

  first_path=""
  staged_uv_bin=""
  for path in ${paths}; do
    if [ -z "${path}" ] || ! [ -f "${path}" ]; then
      echo "uv binary not found after download" >&2
      return 1
    fi
    if [ -z "${first_path}" ]; then
      first_path="${path}"
    fi
    if [ "$(basename "${path}")" = "uv" ]; then
      staged_uv_bin="${path}"
    fi
    $_SUDO install -m 755 "${path}" "/usr/local/bin/$(basename "${path}")"
  done

  if [ -n "${UPGRADE_STAGE_DIR:-}" ]; then
    if [ -z "${staged_uv_bin}" ]; then
      staged_uv_bin="${first_path}"
    fi
    if [ -n "${staged_uv_bin}" ] && [ -x "${staged_uv_bin}" ]; then
      UV_BIN="${staged_uv_bin}"
      export UV_BIN
    fi
  fi

  if [ -n "${UPGRADE_STAGE_DIR:-}" ]; then
    $_SUDO rm -rf "${tmpdir}"
  fi
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
      return 1
    fi
  fi

  uv_bin="${UV_BIN:-/usr/local/bin/uv}"
  if ! [ -x "${uv_bin}" ]; then
    if command -v uv >/dev/null 2>&1; then
      uv_bin="$(command -v uv)"
    else
      echo "uv not installed; run installables/uv.sh" >&2
      return 1
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
}

install_brewx() {
  version="$1"
  set -eo pipefail

  yoink_bin="${YOINK_BIN:-/usr/local/bin/yoink}"
  if ! [ -x "${yoink_bin}" ]; then
    if command -v yoink >/dev/null 2>&1; then
      yoink_bin="$(command -v yoink)"
    else
      echo "yoink not installed; run installables/yoink.sh" >&2
      return 1
    fi
  fi

  if [ -n "${UPGRADE_STAGE_DIR:-}" ]; then
    tmpdir="$(mktemp -d "${UPGRADE_STAGE_DIR}/brewx.XXXXXX")"
  else
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "${tmpdir}"' EXIT
  fi

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

  if [ -n "${UPGRADE_STAGE_DIR:-}" ]; then
    $_SUDO rm -rf "${tmpdir}"
  fi
}

install_cargox() {
  version="$1"
  set -eo pipefail

  yoink_bin="${YOINK_BIN:-/usr/local/bin/yoink}"
  if ! [ -x "${yoink_bin}" ]; then
    if command -v yoink >/dev/null 2>&1; then
      yoink_bin="$(command -v yoink)"
    else
      echo "yoink not installed; run installables/yoink.sh" >&2
      return 1
    fi
  fi

  if [ -n "${UPGRADE_STAGE_DIR:-}" ]; then
    tmpdir="$(mktemp -d "${UPGRADE_STAGE_DIR}/cargox.XXXXXX")"
  else
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "${tmpdir}"' EXIT
  fi

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

  if [ -n "${UPGRADE_STAGE_DIR:-}" ]; then
    $_SUDO rm -rf "${tmpdir}"
  fi
}

install_direnv() {
  version="$1"
  set -eo pipefail

  yoink_bin="${YOINK_BIN:-/usr/local/bin/yoink}"
  if ! [ -x "${yoink_bin}" ]; then
    if command -v yoink >/dev/null 2>&1; then
      yoink_bin="$(command -v yoink)"
    else
      echo "yoink not installed; run installables/yoink.sh" >&2
      return 1
    fi
  fi

  if [ -n "${UPGRADE_STAGE_DIR:-}" ]; then
    tmpdir="$(mktemp -d "${UPGRADE_STAGE_DIR}/direnv.XXXXXX")"
  else
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "${tmpdir}"' EXIT
  fi

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

  if [ -n "${UPGRADE_STAGE_DIR:-}" ]; then
    $_SUDO rm -rf "${tmpdir}"
  fi
}

install_gh() {
  version="$1"
  set -eo pipefail

  yoink_bin="${YOINK_BIN:-/usr/local/bin/yoink}"
  if ! [ -x "${yoink_bin}" ]; then
    if command -v yoink >/dev/null 2>&1; then
      yoink_bin="$(command -v yoink)"
    else
      echo "yoink not installed; run installables/yoink.sh" >&2
      return 1
    fi
  fi

  if [ -n "${UPGRADE_STAGE_DIR:-}" ]; then
    tmpdir="$(mktemp -d "${UPGRADE_STAGE_DIR}/gh.XXXXXX")"
  else
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "${tmpdir}"' EXIT
  fi

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

  if [ -n "${UPGRADE_STAGE_DIR:-}" ]; then
    $_SUDO rm -rf "${tmpdir}"
  fi
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

  if [ -n "${UPGRADE_STAGE_DIR:-}" ]; then
    tmpdir="$(mktemp -d "${UPGRADE_STAGE_DIR}/node.XXXXXX")"
  else
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "${tmpdir}"' EXIT
  fi

  curl -fsSL "${url}" -o "${tmpdir}/${asset}"
  $_SUDO tar -C /usr/local --strip-components=1 --no-same-owner \
    -xzf "${tmpdir}/${asset}"
  $_SUDO rm /usr/local/CHANGELOG.md /usr/local/README.md /usr/local/LICENSE
  $_SUDO rm -rf /usr/local/doc

  if [ -n "${UPGRADE_STAGE_DIR:-}" ]; then
    $_SUDO rm -rf "${tmpdir}"
  fi
}

install_pkgx() {
  version="$1"
  set -eo pipefail

  yoink_bin="${YOINK_BIN:-/usr/local/bin/yoink}"
  if ! [ -x "${yoink_bin}" ]; then
    if command -v yoink >/dev/null 2>&1; then
      yoink_bin="$(command -v yoink)"
    else
      echo "yoink not installed; run installables/yoink.sh" >&2
      return 1
    fi
  fi

  if [ -n "${UPGRADE_STAGE_DIR:-}" ]; then
    tmpdir="$(mktemp -d "${UPGRADE_STAGE_DIR}/pkgx.XXXXXX")"
  else
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "${tmpdir}"' EXIT
  fi

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

  if [ -n "${UPGRADE_STAGE_DIR:-}" ]; then
    $_SUDO rm -rf "${tmpdir}"
  fi
}

is_known_install_target() {
  case "$1" in
    yoink)
      return 0
      ;;
    deno)
      return 0
      ;;
    uv)
      return 0
      ;;
    aws)
      return 0
      ;;
    brewx)
      return 0
      ;;
    cargox)
      return 0
      ;;
    direnv)
      return 0
      ;;
    gh)
      return 0
      ;;
    node)
      return 0
      ;;
    pkgx)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

if [ "${OUTDATED_BOOTSTRAP_ONLY:-0}" -ne 1 ]; then

if version="$(run_step_capture "Checking yoink" outdated_yoink)"; then
  queue_install "yoink" "${version}"
fi

if version="$(run_step_capture "Checking aws" outdated_aws)"; then
  queue_install "aws" "${version}"
fi

if version="$(run_step_capture "Checking brewx" outdated_brewx)"; then
  queue_install "brewx" "${version}"
fi

if version="$(run_step_capture "Checking cargox" outdated_cargox)"; then
  queue_install "cargox" "${version}"
fi

if version="$(run_step_capture "Checking deno" outdated_deno)"; then
  queue_install "deno" "${version}"
fi

if version="$(run_step_capture "Checking direnv" outdated_direnv)"; then
  queue_install "direnv" "${version}"
fi

if version="$(run_step_capture "Checking node" outdated_node)"; then
  queue_install "node" "${version}"
fi

if version="$(run_step_capture "Checking pkgx" outdated_pkgx)"; then
  queue_install "pkgx" "${version}"
fi

if version="$(run_step_capture "Checking uv" outdated_uv)"; then
  queue_install "uv" "${version}"
fi

  emit_plan
fi
}

if [ "${1:-}" = "--internal-run" ]; then
  shift
  run_internal "$@"
elif [ "${1:-}" = "--apply" ]; then
  shift
  OUTDATED_BOOTSTRAP_ONLY=1
  run_outdated >/dev/null
  run_apply "$@"
else
  run_outdated "$@"
fi
__BOOTSTRAP_SCRIPT_EOF__

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

write_stub "${TARGET_DIR}/ffmpeg" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/usr/bin/env -S brewx -! +ffmpeg-full ffmpeg
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
