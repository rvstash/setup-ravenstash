#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'setup-ravenstash: error: %s\n' "$*" >&2
  exit 1
}

write_output() {
  printf '%s=%s\n' "$1" "$2" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
}

requested_version="${INPUT_VERSION:-}"
cache_enabled="${INPUT_CACHE:-true}"
cache_key_suffix="${INPUT_CACHE_KEY_SUFFIX:-}"

case "$cache_enabled" in
  true | false) ;;
  *) fail "cache must be true or false" ;;
esac
if [[ -n "$cache_key_suffix" && ! "$cache_key_suffix" =~ ^[A-Za-z0-9._-]+$ ]]; then
  fail "cache-key-suffix may contain only letters, digits, dot, underscore, and hyphen"
fi
if (( ${#cache_key_suffix} > 128 )); then
  fail "cache-key-suffix must not exceed 128 characters"
fi
[[ -n "$requested_version" ]] \
  || fail "version is required: set it to an exact CLI release such as 0.16.0"
version_pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(rc[1-9][0-9]*)?$'
[[ "$requested_version" =~ $version_pattern ]] \
  || fail "version must be an exact X.Y.Z or X.Y.ZrcN CLI release"
major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
if (( major == 0 && minor < 15 )); then
  fail "version must be 0.15.0 or later; earlier CLI releases have no portable installer"
fi

case "$(uname -s)" in
  Linux)
    if libc_description="$(getconf GNU_LIBC_VERSION 2>/dev/null)"; then
      libc_version="${libc_description#glibc }"
      libc_major="${libc_version%%.*}"
      libc_remainder="${libc_version#*.}"
      libc_minor="${libc_remainder%%.*}"
      if [[ ! "$libc_major" =~ ^[0-9]+$ || ! "$libc_minor" =~ ^[0-9]+$ ]] \
        || (( libc_major < 2 || (libc_major == 2 && libc_minor < 28) )); then
        fail "the portable rvs build requires glibc 2.28 or newer (found ${libc_version})"
      fi
      system_name="linux"
    else
      ldd_output="$(ldd --version 2>&1 || true)"
      grep -qi musl <<<"$ldd_output" || fail "could not identify the Linux libc"
      system_name="linux-musl"
    fi
    ;;
  Darwin)
    macos_version="$(sw_vers -productVersion 2>/dev/null)" \
      || fail "could not identify the macOS version"
    macos_major="${macos_version%%.*}"
    if [[ ! "$macos_major" =~ ^[0-9]+$ ]] || (( macos_major < 14 )); then
      fail "the portable rvs build requires macOS 14 or newer (found ${macos_version})"
    fi
    system_name="macos"
    ;;
  *) fail "this action currently supports Linux and macOS runners" ;;
esac

case "$(uname -m)" in
  x86_64 | amd64) architecture="amd64" ;;
  aarch64 | arm64) architecture="arm64" ;;
  *) fail "unsupported architecture: $(uname -m)" ;;
esac
target="${system_name}-${architecture}"

temporary_root="$(mktemp -d "${RUNNER_TEMP:?RUNNER_TEMP is required}/setup-ravenstash.XXXXXX")"
trap 'rm -rf -- "$temporary_root"' EXIT
installer="${temporary_root}/install.sh"
resolved_version="$requested_version"

tool_cache="${RUNNER_TOOL_CACHE:-${RUNNER_TEMP}/tool-cache}"
cache_root="${tool_cache}/ravenstash/setup-ravenstash/v2/${target}/${resolved_version}"
cache_key="setup-ravenstash-v2-${target}-${resolved_version}"
if [[ -n "$cache_key_suffix" ]]; then
  cache_key="${cache_key}-${cache_key_suffix}"
fi

write_output installer "$installer"
write_output work-root "$temporary_root"
write_output version "$resolved_version"
write_output target "$target"
write_output cache-root "$cache_root"
write_output cache-key "$cache_key"
trap - EXIT
