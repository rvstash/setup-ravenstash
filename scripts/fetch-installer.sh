#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'setup-ravenstash: error: %s\n' "$*" >&2
  exit 1
}

installer="${RVS_SETUP_INSTALLER:?RVS_SETUP_INSTALLER is required}"
version="${RVS_SETUP_VERSION:?RVS_SETUP_VERSION is required}"
work_root="${RVS_SETUP_WORK_ROOT:?RVS_SETUP_WORK_ROOT is required}"
action_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(rc[1-9][0-9]*)?$ ]] \
  || fail "the requested Ravenstash CLI version is invalid"
key="${action_root}/keys/ravenstash-cli.asc"
[[ -f "$key" ]] || fail "the pinned Ravenstash release-signing key is missing"
for command in awk curl gpg install sed; do
  command -v "$command" >/dev/null 2>&1 || fail "required command not found: ${command}"
done

# Use the installer published with the requested release, never a promoted
# "latest" installer, so a job installs exactly what its workflow names.
verification_root="${work_root}/installer-verification"
install -d -m 0700 "$verification_root" "${verification_root}/gnupg"
partial_installer="${installer}.partial"
checksums="${verification_root}/ravenstash-cli-v${version}-checksums.txt"
signature="${checksums}.asc"
release_url="https://github.com/rvstash/ravenstash-cli/releases/download/v${version}"
download() {
  curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL "$1" --output "$2" \
    || fail "could not download $(basename "$1") for Ravenstash CLI ${version}"
}
download "${release_url}/ravenstash-cli-install.sh" "$partial_installer"
download "${release_url}/ravenstash-cli-v${version}-checksums.txt" "$checksums"
download "${release_url}/ravenstash-cli-v${version}-checksums.txt.asc" "$signature"

fingerprint="$(
  gpg --no-options --homedir "${verification_root}/gnupg" --batch --with-colons \
    --import-options show-only --import "$key" 2>/dev/null \
    | awk -F: '$1 == "fpr" { print $10; exit }'
)"
[[ "$fingerprint" == "3B7C20FC370D1A7C813DF3A2E9679F951AD8BAA0" ]] \
  || fail "the bundled release-signing key has an unexpected fingerprint"
gpg --no-options --homedir "${verification_root}/gnupg" --batch \
  --import "$key" >/dev/null 2>&1 \
  || fail "the Ravenstash release-signing key could not be imported"
gpg --no-options --homedir "${verification_root}/gnupg" --batch \
  --verify "$signature" "$checksums" >/dev/null 2>&1 \
  || fail "the Ravenstash release checksum signature is invalid"

expected="$(
  awk '$2 == "ravenstash-cli-install.sh" { print $1; matches += 1 } END { if (matches != 1) exit 1 }' \
    "$checksums"
)" || fail "the signed release inventory must contain exactly one ravenstash-cli-install.sh"
[[ "$expected" =~ ^[[:xdigit:]]{64}$ ]] \
  || fail "the signed installer checksum is invalid"
if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$partial_installer" | awk '{ print $1 }')"
elif command -v shasum >/dev/null 2>&1; then
  actual="$(shasum -a 256 "$partial_installer" | awk '{ print $1 }')"
else
  fail "sha256sum or shasum is required to authenticate the installer"
fi
[[ "$actual" == "$expected" ]] || fail "the Ravenstash installer checksum is invalid"
bash -n "$partial_installer" || fail "the Ravenstash installer is not valid Bash"
installer_version="$(sed -n 's/^readonly release_version="\([^"]*\)"$/\1/p' "$partial_installer")"
[[ "$installer_version" == "$version" ]] \
  || fail "the Ravenstash installer belongs to ${installer_version:-an unknown release}, not ${version}"
grep -Fqx 'readonly portable_installer_api="1"' "$partial_installer" \
  || fail "the Ravenstash ${version} installer does not support portable CI setup"

install -m 0700 "$partial_installer" "$installer"
rm -f -- "$partial_installer"
