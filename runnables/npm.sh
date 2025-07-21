#!/bin/sh

set -eo pipefail

if ! [ -x "${NVM_DIR:-$HOME/.nvm}/nvm-exec" ]; then
  V=$(curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest \
    | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
  NVM_URL="https://raw.githubusercontent.com/nvm-sh/nvm/${V:-master}"
  # unsetting profile prevents mods to shell-rc files
  PROFILE=/dev/null curl -o- "$NVM_URL/install.sh" | bash
fi

source "${NVM_DIR:-$HOME/.nvm}/nvm.sh"

if ! nvm ls > /dev/null 2>&1; then
  nvm install node
fi

nvm unload

if [ ! "$NODE_VERSION" ]; then
  export NODE_VERSION=node
fi

exec "${NVM_DIR:-$HOME/.nvm}"/nvm-exec npm "$@"
