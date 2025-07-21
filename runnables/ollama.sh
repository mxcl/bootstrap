#!/bin/sh

if [ ! -d /Applications/Ollama.app ]; then
  /usr/local/bin/brew install --cask ollama
fi

exec /Applications/Ollama.app/Contents/Resources/ollama "$@"
