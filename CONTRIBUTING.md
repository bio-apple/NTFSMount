# Contributing

NTFSMount is a **personal-use pre-release**. Do not ship or sell it without a written FUSE-T license **and** Developer ID notarization. See [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md).

How to build and run: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md). User-facing history: [CHANGELOG.md](CHANGELOG.md) (do not list uncommitted WIP as shipped). Bug reports: use [.github/ISSUE_TEMPLATE/bug_report.md](.github/ISSUE_TEMPLATE/bug_report.md) (paste `./scripts/ntfsmount diagnose --json`).

## SwiftLint

The project already uses SwiftLint. Config is [`.swiftlint.yml`](.swiftlint.yml) (Sources/ and Tests/ only). There is no Makefile lint target and Package.swift does not invoke it; CI runs:

```bash
brew install swiftlint   # once
swiftlint lint --strict --config .swiftlint.yml
```

Match existing style. Do not turn rules off to land a PR.

## Tests

```bash
swift test
./scripts/test-helper.sh
```

`swift test` covers `NTFSMountCore` unit tests. There is **no** UI test target. `./scripts/test-helper.sh` is a helper selftest: it does not insert a real disk or install the privileged helper.

Real-disk, Gatekeeper, and Finder checks are **manual**: [docs/MANUAL_TEST.md](docs/MANUAL_TEST.md).

## Pull requests

- Branch off `main`. Do not force-push shared `main`.
- PRs that change helper or mount behavior must include a **test plan** (`swift test` / `./scripts/test-helper.sh` / which items from `docs/MANUAL_TEST.md` you ran).
- Do not add sudoers `NOPASSWD` (nothing under `/etc/sudoers.d`).
- Do not silently clear the NTFS hibernation file (`hiberfile`).
- Format / ntfsfix / writable-confirm dialogs stay **Cancel-default**: Return must not confirm a destructive action.
