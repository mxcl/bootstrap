#!/bin/sh

if [ ! -d /Applications/Fork.app ]; then
  /usr/local/bin/brew install --cask codex
fi

exec /opt/homebrew/bin/codex "$@"
