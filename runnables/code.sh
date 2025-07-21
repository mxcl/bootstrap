#!/bin/sh

if ! [ -d /Applications/Visual\ Studio\ Code.app ]; then
  brew install --cask visual-studio-code
fi

exec /Applications/Visual\ Studio\ Code.app/Contents/Resources/app/bin/code "$@"
