#!/bin/bash

set -eo pipefail

DEFAULT_PYTHON_VERSION="3.12"

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script_path="${script_dir}/$(basename "${BASH_SOURCE[0]}")"

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

list_outdated_checks() {
  if [ -f "${script_dir}/outdated/yoink.sh" ]; then
    printf '%s\n' "${script_dir}/outdated/yoink.sh"
  fi
  for x in "${script_dir}"/outdated/*.sh; do
    if ! [ -e "${x}" ]; then
      continue
    fi
    case "$(basename "${x}")" in
    lib.sh|yoink.sh)
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

emit_without_shell_header() {
  local file="$1"

  /usr/bin/awk '
    NR == 1 && /^#!/ { next }
    /^set -euo pipefail$/ { next }
    { print }
  ' "$file"
}

emit_outdated_function() {
  local name="$1"
  local file="$2"

  printf '\n%s() {\n' "$name"
  /usr/bin/awk '
    NR == 1 && /^#!/ { next }
    /^set -euo pipefail$/ { next }
    /^script_path=/ { next }
    /^script_dir=/ { next }
    /script_dir/ { next }
    {
      sub(/exit /, "return ")
      if ($0 == "") { print ""; next }
      print "  " $0
    }
  ' "$file"
  printf '}\n'
}

emit_installable_function() {
  local name="$1"
  local file="$2"

  printf '\n%s() {\n' "$name"
  printf '  version="$1"\n'
  /usr/bin/awk '
    NR == 1 && /^#!/ { next }
    /^set -euo pipefail$/ { next }
    /^script_path=/ { next }
    /^script_dir=/ { next }
    /^outdated_script=/ { next }
    /^if ! version=/ { skipping = 1; next }
    /^version=/ {
      skipping_version = 1
      if ($0 ~ /\)"$/) { skipping_version = 0 }
      next
    }
    skipping {
      if ($0 ~ /^fi$/) { skipping = 0 }
      next
    }
    skipping_version {
      if ($0 ~ /\)"$/) { skipping_version = 0 }
      next
    }
    {
      sub(/exit /, "return ")
      if ($0 == "") { print ""; next }
      print "  " $0
    }
  ' "$file"
  printf '}\n'
}

emit_outdated() {
  local outdated_in="$1"
  local target="/usr/local/bin/outdated"
  local heredoc_delim="__BOOTSTRAP_OUTDATED_SCRIPT_EOF__"

  printf "cat << '%s' > %q\n" "${heredoc_delim}" "${target}"
  cat "${outdated_in}"
  printf '\n'

  emit_without_shell_header "${script_dir}/outdated/lib.sh"

  while IFS= read -r outdated; do
    base="$(basename "${outdated}")"
    name="${base%.*}"
    emit_outdated_function "outdated_${name}" "${outdated}"
  done < <(list_outdated_checks)

  for installable in "${script_dir}"/installables/*.sh; do
    name="$(basename "${installable%.*}")"
    emit_installable_function "install_${name}" "${installable}"
  done

  while IFS= read -r outdated; do
    base="$(basename "${outdated}")"
    name="${base%.*}"
    printf '\nset_step_title "Checking %s"\n' "${name}"
    printf '\nif version="$(outdated_%s)"; then\n' "${name}"
    printf '  queue_install "%s" "${version}"\n' "${name}"
    printf 'fi\n'
  done < <(list_outdated_checks)

  printf '\nemit_plan\n'
  printf '}\n\n'
  cat <<'EOS'
if [ "${1:-}" = "--apply" ]; then
  shift
  run_apply "$@"
else
  run_outdated "$@"
fi
EOS

  printf '%s\n' "${heredoc_delim}"
  printf 'chmod 755 %q\n' "${target}"
  printf 'rm -f %q\n' "/usr/local/bin/upgrade"
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

emit_outdated "${script_dir}/outdated.sh.in"

printf '\n' >&2
printf '%s\n' 'outdated | sh' >&2
