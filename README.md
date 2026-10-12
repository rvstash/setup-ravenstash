# Setup Ravenstash

`setup-ravenstash` installs an authenticated portable `rvs` release and adds it to the GitHub Actions job `PATH`. It deliberately avoids APT, pip, npm, and system-level installation so ephemeral CI jobs start quickly and leave the runner unchanged.

Pin the action to a full commit SHA, which is also the recommended form for privileged publication workflows. A moving `v1` tag will follow the first tagged release.

The action requires CLI 0.15.0 or later. It fails closed instead of silently falling back to APT on Debian-family runners.

## Usage

```yaml
- name: Set up Ravenstash CLI
  uses: rvstash/setup-ravenstash@FULL_COMMIT_SHA
  with:
    version: "0.15.1"
    cache: "true"

- name: Publish
  env:
    RVS_TOKEN: ${{ secrets.RVS_TOKEN }}
  run: |
    rvs art select platform/releases
    rvs npm --rvs-yes publish
```

`rvs` acts for the account that owns `RVS_TOKEN`, so the job does not select an account.

The action is install-only. It never receives, stores, or forwards `RVS_TOKEN`. Keep credentials on the shortest possible later step.

## Inputs

| Input | Default | Description |
|---|---:|---|
| `version` | `latest` | Exact `X.Y.Z`/`X.Y.ZrcN` release or the version embedded in the promoted installer. Pin an exact version for reproducible publication. |
| `cache` | `true` | Restore and save the verified extracted bundle using GitHub Actions cache. |
| `cache-key-suffix` | empty | Explicit cache-busting suffix of at most 128 letters, digits, `.`, `_`, or `-`. |
| `github-token` | empty | Optional token for release-asset download. Public stable releases do not require one. |

## Outputs

| Output | Description |
|---|---|
| `version` | Exact installed CLI version. |
| `cache-hit` | `true` when the exact installation came from Actions cache. |
| `rvs-path` | Absolute path to the executable. |

## Performance and security

For an exact version, cache lookup happens before any network or OpenPGP work. On a cache miss the action downloads the small promoted installer and one native portable release bundle plus its signed checksum material. The installer verifies the pinned OpenPGP key, detached signature, and archive SHA-256 before activation. Verification cannot be disabled.

The action also bundles the public release-signing key and independently verifies the downloaded installer against its signed release inventory before executing it. This prevents the installer delivery endpoint from replacing its own trust root.

The cache key includes action schema, OS/libc, architecture, exact CLI version, and the optional suffix. Restored command links are rebuilt relative to the cache root, so caches remain portable across runner tool-cache locations. Only the verified public bundle and its non-secret install receipt are cached. Ravenstash credentials and GitHub tokens are never cached.

GitHub-hosted runners are ephemeral, so the runner tool cache alone does not span jobs. The optional Actions cache does; whether it beats the GitHub Release CDN depends on bundle size and locality. Set `cache: "false"` when measurement shows a cold verified download is faster for a particular workflow.

The first release supports Linux glibc/musl and macOS on amd64 and arm64; its CI matrix covers the corresponding GitHub-hosted Ubuntu and macOS runners. Windows should be added only after its PowerShell installer can provide the same exact-version portable contract and cache verification coverage.

## Development

```bash
bash tests/test-setup.sh
bash -n scripts/*.sh tests/*.sh
shellcheck scripts/*.sh tests/*.sh
```

This project is licensed under Apache License 2.0.
