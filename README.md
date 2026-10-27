# Setup Ravenstash

`setup-ravenstash` installs an authenticated portable `rvs` release and adds it to the GitHub Actions job `PATH`. It deliberately avoids APT, pip, npm, and system-level installation so ephemeral CI jobs start quickly and leave the runner unchanged.

The action installs exactly the CLI version your workflow names. It never resolves a "latest" release, so the installed CLI changes only when the workflow changes. The CLI is pre-1.0 and can change commands between minor releases; read its [changelog](https://github.com/rvstash/ravenstash-cli/blob/main/CHANGELOG.md) before raising `version`.

The action requires CLI 0.15.0 or later. It fails closed instead of silently falling back to APT on Debian-family runners.

## Usage

```yaml
- name: Set up Ravenstash CLI
  uses: rvstash/setup-ravenstash@FULL_COMMIT_SHA # v0.1.0
  with:
    version: "0.16.0"

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
| `version` | required | Exact CLI release to install, as `X.Y.Z` or `X.Y.ZrcN`, 0.15.0 or later. |
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

Cache lookup happens before any network or OpenPGP work. On a cache miss the action downloads the installer published with the requested CLI release, that release's signed checksum inventory, and one native portable bundle. Verification cannot be disabled:

- The action bundles the public release-signing key. Before running the installer, it verifies the inventory signature, the installer's SHA-256, and that the installer belongs to the requested release.
- The installer then verifies the same key, detached signature, and archive SHA-256 before activation.

The cache key includes action schema, OS/libc, architecture, exact CLI version, and the optional suffix. Restored command links are rebuilt relative to the cache root, so caches remain portable across runner tool-cache locations. Only the verified public bundle and its non-secret install receipt are cached. Ravenstash credentials and GitHub tokens are never cached.

GitHub-hosted runners are ephemeral, so the runner tool cache alone does not span jobs. The optional Actions cache does; whether it beats the GitHub Release CDN depends on bundle size and locality. Set `cache: "false"` when measurement shows a cold verified download is faster for a particular workflow.

The first release supports Linux glibc/musl and macOS on amd64 and arm64; its CI matrix covers the corresponding GitHub-hosted Ubuntu and macOS runners. Windows should be added only after its PowerShell installer can provide the same exact-version portable contract and cache verification coverage.

## Development

```bash
bash tests/test-setup.sh
bash -n scripts/*.sh tests/*.sh
shellcheck scripts/*.sh tests/*.sh
```

## Versioning

The action has its own version, independent of the CLI it installs. Releases are immutable `vX.Y.Z` tags. While the action is 0.x, a minor release may change inputs or behavior; patch releases do not. Pin the full commit SHA with the tag as a comment, as in the usage example, so Dependabot or Renovate can propose action updates. A CLI release does not need a new action release.

This project is licensed under Apache License 2.0.
