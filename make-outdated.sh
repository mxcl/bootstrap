#!/bin/bash

set -eo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

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

cat "${script_dir}/outdated.sh.in"
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

printf '\nif [ "${OUTDATED_BOOTSTRAP_ONLY:-0}" -ne 1 ]; then\n'

while IFS= read -r outdated; do
  base="$(basename "${outdated}")"
  name="${base%.*}"
  printf '\nif version="$(run_step_capture "Checking %s" outdated_%s)"; then\n' \
    "${name}" "${name}"
  printf '  queue_install "%s" "${version}"\n' "${name}"
  printf 'fi\n'
done < <(list_outdated_checks)

printf '\n  emit_plan\n'
printf 'fi\n'
printf '}\n\n'
cat <<'EOF'
if [ "${1:-}" = "--internal-run" ]; then
  shift
  run_internal "$@"
elif [ "${1:-}" = "--apply" ]; then
  shift
  run_apply "$@"
else
  run_outdated "$@"
fi
EOF
