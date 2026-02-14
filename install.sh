#!/bin/bash

set -eo pipefail

DEFAULT_PYTHON_VERSION="3.12"

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

list_installables() {
  if [ -f "${script_dir}/installables/yoink.sh" ]; then
    printf '%s\n' "${script_dir}/installables/yoink.sh"
  fi
  if [ -f "${script_dir}/installables/deno.sh" ]; then
    printf '%s\n' "${script_dir}/installables/deno.sh"
  fi
  for x in "${script_dir}"/installables/*.sh; do
    if ! [ -e "${x}" ]; then
      continue
    fi
    case "$(basename "${x}")" in
    yoink.sh|deno.sh)
      continue
      ;;
    esac
    printf '%s\n' "${x}"
  done
}

if [ "${1:-}" = "--list-installables" ]; then
  list_installables
  exit 0
fi

emit_outdated_install_commands() {
  local target="/usr/local/bin/outdated"

  printf '%q > %q\n' "${script_dir}/make-outdated.sh" "${target}"
  printf 'chmod 755 %q\n' "${target}"
}

echo '# Runnables'

for X in "$script_dir"/runnables/*; do
  base="$(basename "${X}")"
  case "${base}" in
  *.sh.in)
    continue
    ;;
  esac

  x="${base%.*}"
  case "${x}" in
  python|pip)
    for y in 3.10 3.11 3.12 3.13; do
      target="/usr/local/bin/${x}$y"
      printf 'install -m 755 %q %q\n' "$X" "$target"
      printf 'sed -i %q %q %q\n' '' "s|^_python_version=|_python_version=$y|" "$target"
    done

    printf 'rm -f %q\n' "/usr/local/bin/${x}"
    printf 'ln -s %q %q\n' "${x}3" "/usr/local/bin/${x}"

    printf 'rm -f %q\n' "/usr/local/bin/${x}3"
    printf 'ln -s %q %q\n' "${x}${DEFAULT_PYTHON_VERSION}" "/usr/local/bin/${x}3"
    ;;
  *)
    printf 'install -m 755 %q %q\n' "$X" "/usr/local/bin/${x}"
    ;;
  esac
done

emit_outdated_install_commands

printf '\n' >&2
printf '%s\n' 'outdated | sh' >&2
