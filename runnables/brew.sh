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
