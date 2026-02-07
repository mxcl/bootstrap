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

emit_upgrade() {
  local upgrade_in="$1"
  local target="/usr/local/bin/upgrade"

  printf "cat << 'EOF' > %q\n" "${target}"
  cat "${upgrade_in}"
  printf '\n'

  emit_without_shell_header "${script_dir}/outdated/lib.sh"

  for outdated in "${script_dir}"/outdated/*.sh; do
    base="$(basename "${outdated}")"
    if [ "${base}" = "lib.sh" ]; then
      continue
    fi
    name="${base%.*}"
    emit_outdated_function "outdated_${name}" "${outdated}"
  done

  for installable in "${script_dir}"/installables/*.sh; do
    name="$(basename "${installable%.*}")"
    emit_installable_function "install_${name}" "${installable}"
  done

  for outdated in "${script_dir}"/outdated/*.sh; do
    base="$(basename "${outdated}")"
    if [ "${base}" = "lib.sh" ]; then
      continue
    fi
    name="${base%.*}"
    printf '\ngum format "# Checking %s"\n' "${name}"
    printf '\nif version="$(outdated_%s)"; then\n' "${name}"
    printf '  install_%s "${version}"\n' "${name}"
    printf 'fi\n'
  done

  printf 'EOF\n'
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

emit_upgrade "${script_dir}/upgrade.sh.in"

if ! [ -x /Library/Developer/CommandLineTools/usr/bin/git ]; then
  echo
  echo '# Install Xcode Command Line Tools:'
  printf 'xcode-select --install\n'
fi

echo
echo '# Installables'
while IFS= read -r installable; do
  printf '%q\n' "${installable}"
done < <(list_installables)

if ! [ -d /opt/homebrew ]; then
  echo
  echo '# brew harnass'

  user="${USER:-$(id -un)}"

  echo 'install -d -o root -g wheel -m 0755 /opt/homebrew'
  for x in \
    bin etc include lib sbin opt Cellar Caskroom Frameworks \
    share/zsh/site-functions var/homebrew/linked var/log
  do
    echo "mkdir -p /opt/homebrew/$x"
  done

  echo "chown -R $user:admin /opt/homebrew"
  echo "chmod -R ug=rwx,go=rx /opt/homebrew"
  echo "chmod go-w /opt/homebrew/share/zsh /opt/homebrew/share/zsh/site-functions"

  echo "chown -R $user:admin /opt/homebrew"
fi

printf '\n' >&2
printf 'run: to apply, run: %q 2>/dev/null | sudo bash -exo pipefail\n' "${BASH_SOURCE[0]}" >&2
