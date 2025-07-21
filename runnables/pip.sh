#!/bin/sh

set -eo pipefail

_python_version=

if ! _python_path="$(/usr/local/bin/uv python find --managed-python "$_python_version" 2>/dev/null)"; then
  /usr/local/bin/uv python install --managed-python "$_python_version"
  _python_path="$(/usr/local/bin/uv python find --managed-python "$_python_version")"
fi

exec "$(dirname "$_python_path")"/pip "$@"
