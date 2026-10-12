#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary_directory="$(mktemp -d)"
trap 'rm -rf -- "$temporary_directory"' EXIT

mock_installer="${temporary_directory}/mock-install.sh"
cat > "$mock_installer" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
readonly release_version="0.15.1"
readonly portable_installer_api="1"
test "${RVS_INSTALL_METHOD}" = portable
test "${RVS_INSTALL_SCOPE}" = user
test "${RVS_INSTALL_REPAIR}" = 1
selected="${RVS_INSTALL_VERSION:-${release_version}}"
version_root="${RVS_INSTALL_ROOT}/${selected}"
mkdir -p "$version_root" "${RVS_INSTALL_BIN_DIR}"
for command_name in rvs ravenstash docker-credential-rvs; do
  cat > "${version_root}/${command_name}" <<SCRIPT
#!/usr/bin/env bash
printf 'Ravenstash CLI %s\\n' '${selected}'
SCRIPT
  chmod 0755 "${version_root}/${command_name}"
  ln -s "${version_root}/${command_name}" "${RVS_INSTALL_BIN_DIR}/${command_name}"
done
ln -s "$selected" "${RVS_INSTALL_ROOT}/current"
MOCK
chmod 0755 "$mock_installer"

mock_bin="${temporary_directory}/mock-bin"
mkdir -p "$mock_bin"
cat > "${mock_bin}/curl" <<'MOCK_CURL'
#!/usr/bin/env bash
set -euo pipefail
output=""
url=""
while (( $# > 0 )); do
  case "$1" in
    -o | --output)
      output="$2"
      shift 2
      ;;
    https://*)
      url="$1"
      shift
      ;;
    *) shift ;;
  esac
done
test -n "$output"
printf '%s\n' "$url" >> "${MOCK_CURL_LOG}"
case "$url" in
  https://ravenstash.com/install.sh)
    cp "${MOCK_INSTALLER_SOURCE}" "$output"
    ;;
  *.asc)
    printf 'mock signature\n' > "$output"
    ;;
  *-checksums.txt)
    if [[ "${MOCK_BAD_CHECKSUM:-0}" == 1 ]]; then
      checksum="0000000000000000000000000000000000000000000000000000000000000000"
    elif command -v sha256sum >/dev/null 2>&1; then
      checksum="$(sha256sum "${RVS_SETUP_INSTALLER}.partial" | awk '{ print $1 }')"
    else
      checksum="$(shasum -a 256 "${RVS_SETUP_INSTALLER}.partial" | awk '{ print $1 }')"
    fi
    printf '%s  ravenstash-cli-install.sh\n' "$checksum" > "$output"
    ;;
  *)
    printf 'unexpected mock download: %s\n' "$url" >&2
    exit 1
    ;;
esac
MOCK_CURL
cat > "${mock_bin}/gpg" <<'MOCK_GPG'
#!/usr/bin/env bash
set -euo pipefail
# A fresh runner has no default GnuPG home, and --no-options does not create
# one: every call must name the action's own temporary home.
[[ " $* " == *" --homedir "* ]] || { echo "gpg called without --homedir" >&2; exit 2; }
for argument in "$@"; do
  if [[ "$argument" == --with-colons ]]; then
    printf 'fpr:::::::::3B7C20FC370D1A7C813DF3A2E9679F951AD8BAA0:\n'
    break
  fi
done
MOCK_GPG
chmod 0755 "${mock_bin}/curl" "${mock_bin}/gpg"

export PATH="${mock_bin}:${PATH}"
export MOCK_INSTALLER_SOURCE="$mock_installer"
export MOCK_CURL_LOG="${temporary_directory}/curl.log"
export RUNNER_TEMP="${temporary_directory}/runner"
export RUNNER_TOOL_CACHE="${temporary_directory}/tools"
export INPUT_VERSION="0.15.0"
export INPUT_CACHE=true
export INPUT_CACHE_KEY_SUFFIX=fixture
export GITHUB_OUTPUT="${temporary_directory}/prepare.out"
mkdir -p "$RUNNER_TEMP" "$RUNNER_TOOL_CACHE"

# An exact-version prepare is network-free, so a cache hit needs no installer.
bash "${root}/scripts/prepare.sh"
test ! -e "$MOCK_CURL_LOG"
grep -Fx 'version=0.15.0' "$GITHUB_OUTPUT"
expected_system=""
expected_architecture=""
case "$(uname -s)" in
  Linux)
    if getconf GNU_LIBC_VERSION >/dev/null 2>&1; then
      expected_system=linux
    else
      expected_system=linux-musl
    fi
    ;;
  Darwin) expected_system=macos ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) expected_architecture=amd64 ;;
  aarch64 | arm64) expected_architecture=arm64 ;;
esac
expected_target="${expected_system}-${expected_architecture}"
grep -Fx "target=${expected_target}" "$GITHUB_OUTPUT"
grep -Fx "cache-key=setup-ravenstash-v2-${expected_target}-0.15.0-fixture" "$GITHUB_OUTPUT"

installer="$(sed -n 's/^installer=//p' "$GITHUB_OUTPUT")"
work_root="$(sed -n 's/^work-root=//p' "$GITHUB_OUTPUT")"
version="$(sed -n 's/^version=//p' "$GITHUB_OUTPUT")"
cache_root="$(sed -n 's/^cache-root=//p' "$GITHUB_OUTPUT")"

# A miss authenticates the installer once; a second call reuses that result.
export RVS_SETUP_INSTALLER="$installer"
export RVS_SETUP_WORK_ROOT="$work_root"
test "$(bash "${root}/scripts/fetch-installer.sh")" = 0.15.1
release_assets="https://github.com/rvstash/ravenstash-cli/releases/download/v0.15.1"
grep -Fx "${release_assets}/ravenstash-cli-v0.15.1-checksums.txt" "$MOCK_CURL_LOG"
grep -Fx "${release_assets}/ravenstash-cli-v0.15.1-checksums.txt.asc" "$MOCK_CURL_LOG"
test "$(grep -c -v -e '^https://ravenstash.com/install.sh$' -e "^${release_assets}/" "$MOCK_CURL_LOG")" = 0
test "$(wc -l < "$MOCK_CURL_LOG")" -eq 3
test "$(bash "${root}/scripts/fetch-installer.sh")" = 0.15.1
test "$(wc -l < "$MOCK_CURL_LOG")" -eq 3

RVS_SETUP_VERSION="$version" \
RVS_SETUP_CACHE_ROOT="$cache_root" \
  bash "${root}/scripts/install.sh"

export RVS_SETUP_VERSION="$version"
export RVS_SETUP_CACHE_ROOT="$cache_root"
export GITHUB_PATH="${temporary_directory}/path.out"
export GITHUB_OUTPUT="${temporary_directory}/activate.out"
bash "${root}/scripts/activate.sh"
grep -Fx "${cache_root}/bin" "$GITHUB_PATH"
grep -Fx "rvs-path=${cache_root}/bin/rvs" "$GITHUB_OUTPUT"
test "$(readlink "${cache_root}/versions/current")" = 0.15.0
test "$(readlink "${cache_root}/bin/rvs")" = ../versions/current/rvs

# Cached command links remain valid if the tool-cache root changes.
relocated_cache="${temporary_directory}/relocated-cache"
cp -a "$cache_root" "$relocated_cache"
rm -rf -- "$cache_root"
export RVS_SETUP_CACHE_ROOT="$relocated_cache"
export GITHUB_PATH="${temporary_directory}/relocated-path.out"
export GITHUB_OUTPUT="${temporary_directory}/relocated-activate.out"
bash "${root}/scripts/activate.sh"
grep -Fx "rvs-path=${relocated_cache}/bin/rvs" "$GITHUB_OUTPUT"

export RESOLVED_VERSION="$version"
export RESTORED_CACHE_HIT=true
export RESOLVED_RVS_PATH="${relocated_cache}/bin/rvs"
export GITHUB_OUTPUT="${temporary_directory}/result.out"
bash "${root}/scripts/result.sh"
grep -Fx 'cache-hit=true' "$GITHUB_OUTPUT"
RESTORED_CACHE_HIT="" GITHUB_OUTPUT="${temporary_directory}/result-miss.out" \
  bash "${root}/scripts/result.sh"
grep -Fx 'cache-hit=false' "${temporary_directory}/result-miss.out"

if INPUT_CACHE=maybe GITHUB_OUTPUT="${temporary_directory}/bad-cache.out" \
  bash "${root}/scripts/prepare.sh" 2>/dev/null; then
  printf 'expected invalid cache input to fail\n' >&2
  exit 1
fi
if INPUT_VERSION=1.2 GITHUB_OUTPUT="${temporary_directory}/bad-version.out" \
  bash "${root}/scripts/prepare.sh" 2>/dev/null; then
  printf 'expected invalid version input to fail\n' >&2
  exit 1
fi
if INPUT_VERSION=0.15.2rc0 GITHUB_OUTPUT="${temporary_directory}/bad-rc.out" \
  bash "${root}/scripts/prepare.sh" 2>/dev/null; then
  printf 'expected release candidate zero to fail\n' >&2
  exit 1
fi
printf -v long_suffix '%0130d' 0
if INPUT_CACHE_KEY_SUFFIX="$long_suffix" GITHUB_OUTPUT="${temporary_directory}/long-key.out" \
  bash "${root}/scripts/prepare.sh" 2>/dev/null; then
  printf 'expected an oversized cache suffix to fail\n' >&2
  exit 1
fi

# Latest resolves the signed promoted installer before cache lookup.
rm -f -- "$MOCK_CURL_LOG"
export INPUT_VERSION=latest
export INPUT_CACHE_KEY_SUFFIX=""
export GITHUB_OUTPUT="${temporary_directory}/latest.out"
bash "${root}/scripts/prepare.sh"
grep -Fx 'version=0.15.1' "$GITHUB_OUTPUT"
test "$(wc -l < "$MOCK_CURL_LOG")" -eq 3
latest_work_root="$(sed -n 's/^work-root=//p' "$GITHUB_OUTPUT")"

# Contract and checksum failures remain fail-closed.
incompatible_installer="${temporary_directory}/incompatible-install.sh"
grep -v 'portable_installer_api' "$mock_installer" > "$incompatible_installer"
export MOCK_INSTALLER_SOURCE="$incompatible_installer"
if GITHUB_OUTPUT="${temporary_directory}/incompatible.out" \
  bash "${root}/scripts/prepare.sh" 2>/dev/null; then
  printf 'expected an incompatible installer to fail\n' >&2
  exit 1
fi
export MOCK_INSTALLER_SOURCE="$mock_installer"
if MOCK_BAD_CHECKSUM=1 GITHUB_OUTPUT="${temporary_directory}/bad-checksum.out" \
  bash "${root}/scripts/prepare.sh" 2>/dev/null; then
  printf 'expected an invalid installer checksum to fail\n' >&2
  exit 1
fi

# Version checks are exact rather than substring matches.
printf '#!/usr/bin/env bash\nprintf "Ravenstash CLI 0.15.50\\n"\n' \
  > "${relocated_cache}/versions/0.15.0/rvs"
chmod 0755 "${relocated_cache}/versions/0.15.0/rvs"
if GITHUB_OUTPUT="${temporary_directory}/wrong-version.out" \
  bash "${root}/scripts/activate.sh" 2>/dev/null; then
  printf 'expected a mismatched executable version to fail\n' >&2
  exit 1
fi

RVS_SETUP_WORK_ROOT="$work_root" bash "${root}/scripts/cleanup.sh"
test ! -e "$work_root"
RVS_SETUP_WORK_ROOT="$latest_work_root" bash "${root}/scripts/cleanup.sh"
test ! -e "$latest_work_root"
outside_cleanup_root="${temporary_directory}/keep"
mkdir -p "$outside_cleanup_root"
if RVS_SETUP_WORK_ROOT="$outside_cleanup_root" bash "${root}/scripts/cleanup.sh" 2>/dev/null; then
  printf 'expected cleanup outside its private prefix to fail\n' >&2
  exit 1
fi
test -d "$outside_cleanup_root"

printf 'setup-ravenstash tests passed\n'
