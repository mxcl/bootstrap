#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RUNNABLES_DIR="${ROOT}/runnables"
OUTDATED_DIR="${ROOT}/outdated"
OUTDATED_TEMPLATE="${ROOT}/outdated.sh.in"
MAKE_OUTDATED="${ROOT}/make-outdated.sh"
OUTPUT="${1:-${ROOT}/setup.sh}"
OUTPUT_DIR=$(dirname "${OUTPUT}")

DEFAULT_PYTHON_VERSION="3.12"
PYTHON_VERSIONS="3.10 3.11 3.12 3.13"
DELIMITER="__BOOTSTRAP_SCRIPT_EOF__"

for search_path in "${RUNNABLES_DIR}" "${OUTDATED_DIR}" "${OUTDATED_TEMPLATE}" \
  "${MAKE_OUTDATED}"
do
  if grep -R -n "^${DELIMITER}$" "${search_path}" >/dev/null 2>&1; then
    printf '%s\n' "make-setup: delimiter collision: ${DELIMITER}" >&2
    exit 1
  fi
done

emit_outdated_content() {
  "${MAKE_OUTDATED}"
}

mkdir -p "${OUTPUT_DIR}"

TMP_FILE=$(mktemp)

{
  cat <<HEADER
#!/bin/sh
set -eo pipefail

DEFAULT_PYTHON_VERSION="${DEFAULT_PYTHON_VERSION}"
PYTHON_VERSIONS="${PYTHON_VERSIONS}"
TARGET_DIR="/usr/local/bin"
_SUDO=sudo

umask 022

if [ ! -d "\${TARGET_DIR}" ]; then
  mkdir -p "\${TARGET_DIR}"
fi

if [ ! -w "\${TARGET_DIR}" ]; then
  printf '%s\n' "setup: \${TARGET_DIR} not writable; try running with sudo" >&2
  exit 1
fi

if [ ! -d /opt/homebrew ]; then
  user="\${SUDO_USER:-\${USER:-\$(id -un)}}"

  install -d -o root -g wheel -m 0755 /opt/homebrew
  for x in \
    bin etc include lib sbin opt Cellar Caskroom Frameworks \
    share/zsh/site-functions var/homebrew/linked var/log
  do
    mkdir -p "/opt/homebrew/\${x}"
  done

  chown -R "\${user}:admin" /opt/homebrew
  chmod -R ug=rwx,go=rx /opt/homebrew
  chmod go-w /opt/homebrew/share/zsh /opt/homebrew/share/zsh/site-functions

  chown -R "\${user}:admin" /opt/homebrew
fi

write_stub() {
  target="\$1"
  cat >"\${target}"
  chmod 755 "\${target}"
}

install_python() {
  for version in \${PYTHON_VERSIONS}; do
    target="\${TARGET_DIR}/python\${version}"
    write_stub "\${target}" <<'${DELIMITER}'
HEADER
  cat "${RUNNABLES_DIR}/python.sh"
  cat <<HEADER
${DELIMITER}
    sed -i '' "s|^_python_version=|_python_version=\${version}|" "\${target}"
  done

  rm -f "\${TARGET_DIR}/python"
  ln -s "python3" "\${TARGET_DIR}/python"

  rm -f "\${TARGET_DIR}/python3"
  ln -s "python\${DEFAULT_PYTHON_VERSION}" "\${TARGET_DIR}/python3"
}

install_pip() {
  for version in \${PYTHON_VERSIONS}; do
    target="\${TARGET_DIR}/pip\${version}"
    write_stub "\${target}" <<'${DELIMITER}'
HEADER
  cat "${RUNNABLES_DIR}/pip.sh"
  cat <<HEADER
${DELIMITER}
    sed -i '' "s|^_python_version=|_python_version=\${version}|" "\${target}"
  done

  rm -f "\${TARGET_DIR}/pip"
  ln -s "pip3" "\${TARGET_DIR}/pip"

  rm -f "\${TARGET_DIR}/pip3"
  ln -s "pip\${DEFAULT_PYTHON_VERSION}" "\${TARGET_DIR}/pip3"
}

install_python
install_pip

write_stub "\${TARGET_DIR}/outdated" <<'${DELIMITER}'
HEADER
  emit_outdated_content
  cat <<HEADER
${DELIMITER}
HEADER

  for script in "${RUNNABLES_DIR}"/*.sh; do
    name=$(basename "${script%.*}")
    case "${name}" in
      python|pip)
        continue
        ;;
    esac

    cat <<HEADER

write_stub "\${TARGET_DIR}/${name}" <<'${DELIMITER}'
HEADER
    cat "${script}"
    cat <<HEADER
${DELIMITER}
HEADER
  done
} > "${TMP_FILE}"

chmod 755 "${TMP_FILE}"
mv "${TMP_FILE}" "${OUTPUT}"
