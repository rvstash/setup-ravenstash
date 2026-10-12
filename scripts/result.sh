#!/usr/bin/env bash
set -euo pipefail

cache_hit="${RESTORED_CACHE_HIT:-false}"
[[ "$cache_hit" == "true" ]] || cache_hit=false

{
  printf 'version=%s\n' "${RESOLVED_VERSION:?RESOLVED_VERSION is required}"
  printf 'cache-hit=%s\n' "$cache_hit"
  printf 'rvs-path=%s\n' "${RESOLVED_RVS_PATH:?RESOLVED_RVS_PATH is required}"
} >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
