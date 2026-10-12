#!/usr/bin/env bash
set -euo pipefail

version="${RVS_SETUP_VERSION:?RVS_SETUP_VERSION is required}"
cache_root="${RVS_SETUP_CACHE_ROOT:?RVS_SETUP_CACHE_ROOT is required}"
versions_directory="${cache_root}/versions"
version_directory="${versions_directory}/${version}"
bin_directory="${cache_root}/bin"
rvs_path="${bin_directory}/rvs"

fail() {
  printf 'setup-ravenstash: error: %s\n' "$*" >&2
  exit 1
}

[[ -d "$version_directory" && ! -L "$version_directory" ]] \
  || fail "the installation does not contain version ${version}"
[[ -f "${version_directory}/rvs" && ! -L "${version_directory}/rvs" \
  && -x "${version_directory}/rvs" ]] \
  || fail "the installation does not contain a regular executable rvs"

# The portable installer uses absolute command links. Rebuild them as relative
# links so an Actions cache can move between runners with different tool roots.
install -d -m 0755 "$bin_directory"
if [[ -e "${versions_directory}/current" && ! -L "${versions_directory}/current" ]]; then
  fail "the installation's current pointer is not a symlink"
fi
ln -sfn "$version" "${versions_directory}/current"
for command_name in rvs ravenstash docker-credential-rvs; do
  command_source="${version_directory}/${command_name}"
  command_path="${bin_directory}/${command_name}"
  if [[ -e "$command_path" && ! -L "$command_path" ]]; then
    fail "${command_path} is not an installer-owned symlink"
  fi
  if [[ -e "$command_source" ]]; then
    ln -sfn "../versions/current/${command_name}" "$command_path"
  fi
done

reported_version="$("$rvs_path" --version)"
[[ "$reported_version" == "Ravenstash CLI ${version}" ]] \
  || fail "expected Ravenstash CLI ${version}, got ${reported_version}"

printf '%s\n' "$bin_directory" >> "${GITHUB_PATH:?GITHUB_PATH is required}"
printf 'rvs-path=%s\n' "$rvs_path" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
printf 'setup-ravenstash: ready: %s\n' "$reported_version"
