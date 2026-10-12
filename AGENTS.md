# AGENTS.md

This repository owns the public `setup-ravenstash` GitHub Action. The action installs an authenticated, self-contained Ravenstash CLI archive and adds it to the job PATH.

## Boundaries

- Keep this an install-only action. Do not perform login, accept `RVS_TOKEN`, select an account or repository, or publish packages.
- Use the Ravenstash CLI's signed portable installer path. Do not use APT, pip, npm, Homebrew, or another package manager to install `rvs`.
- Signature and checksum verification are mandatory and cannot be disabled.
- Keep the release-signing public key pinned in `keys/`; key rotation requires an explicitly reviewed action update before a CLI release trusts the new key.
- Caches may contain only verified public CLI bundles and non-secret receipts.
- Keep the initial action compatible with GitHub-hosted Linux and macOS runners. Add Windows only with equivalent release authentication and tests.
- Pin every third-party action by full commit SHA.

## Verification

Run from this repository:

```bash
bash tests/test-setup.sh
bash -n scripts/*.sh tests/*.sh
shellcheck scripts/*.sh tests/*.sh
```

Do not commit, push, tag, release, publish, or create a Marketplace listing unless the user explicitly requests it.
