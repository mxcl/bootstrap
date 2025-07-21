#!/bin/sh

set -eo pipefail

if [ -x /Library/Developer/CommandLineTools/usr/bin/python3 ]; then
  exec /Library/Developer/CommandLineTools/usr/bin/python3 "$@"
fi

if ! _python_path="$(/usr/local/bin/uv python find --managed-python 3.9 2>/dev/null)"; then
  /usr/local/bin/uv python install --managed-python 3.9
  _python_path="$(/usr/local/bin/uv python find --managed-python 3.9)"
fi

exec "$_python_path" "$@"
