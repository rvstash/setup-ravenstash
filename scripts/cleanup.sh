#!/usr/bin/env bash
set -euo pipefail

work_root="${RVS_SETUP_WORK_ROOT:-}"
if [[ -z "$work_root" ]]; then
  exit 0
fi

case "$work_root" in
  "${RUNNER_TEMP:?RUNNER_TEMP is required}"/setup-ravenstash.*)
    rm -rf -- "$work_root"
    ;;
  *)
    printf 'setup-ravenstash: refusing to clean unexpected path: %s\n' "$work_root" >&2
    exit 1
    ;;
esac
