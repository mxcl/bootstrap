#!/bin/sh

if [ ! -d /Applications/Fork.app ]; then
  /usr/local/bin/brew install --cask fork
fi

exec /Applications/Fork.app/Contents/Resources/fork_cli "$@"
