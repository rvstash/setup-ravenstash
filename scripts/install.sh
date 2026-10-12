#!/usr/bin/env bash
set -euo pipefail

installer="${RVS_SETUP_INSTALLER:?RVS_SETUP_INSTALLER is required}"
version="${RVS_SETUP_VERSION:?RVS_SETUP_VERSION is required}"
cache_root="${RVS_SETUP_CACHE_ROOT:?RVS_SETUP_CACHE_ROOT is required}"

export RVS_INSTALL_METHOD=portable
export RVS_INSTALL_SCOPE=user
export RVS_INSTALL_ROOT="${cache_root}/versions"
export RVS_INSTALL_BIN_DIR="${cache_root}/bin"
export RVS_INSTALL_NO_BANNER=1
export RVS_INSTALL_NO_HINTS=1
export RVS_INSTALL_REPAIR=1
export RVS_INSTALL_VERSION="$version"
if [[ -n "${RVS_SETUP_GITHUB_TOKEN:-}" ]]; then
  export RVS_GITHUB_TOKEN="$RVS_SETUP_GITHUB_TOKEN"
fi

bash "$installer"
