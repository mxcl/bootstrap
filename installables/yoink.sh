#!/bin/sh
set -eo pipefail

curl -fsSL https://yoink.sh |
  $_SUDO sh -s -- -C /usr/local/bin mxcl/yoink
