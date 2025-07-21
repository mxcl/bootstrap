#!/bin/sh

set -eo pipefail

if [ -x /Library/Developer/CommandLineTools/usr/bin/jq ]; then
  exec /Library/Developer/CommandLineTools/usr/bin/jq "$@"
fi

exec /usr/local/bin/brewx jq "$@"
