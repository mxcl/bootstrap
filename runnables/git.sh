#!/bin/sh

set -eo pipefail

if [ -x /Library/Developer/CommandLineTools/usr/bin/git ]; then
  exec /Library/Developer/CommandLineTools/usr/bin/git "$@"
fi

exec /usr/local/bin/brewx git "$@"
