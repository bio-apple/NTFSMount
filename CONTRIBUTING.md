# Contributing

NTFSMount is a **personal-use pre-release**. Do not ship or sell it without a written FUSE-T license **and** Developer ID notarization. See [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md).

How to build and run: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md). User-facing history: [CHANGELOG.md](CHANGELOG.md) (do not list uncommitted WIP as shipped). Bug reports: use [.github/ISSUE_TEMPLATE/bug_report.md](.github/ISSUE_TEMPLATE/bug_report.md) (attach the in-app diagnostic zip, or paste `./scripts/ntfsmount diagnose --json`).

## SwiftLint

The project already uses SwiftLint. Config is [`.swiftlint.yml`](.swiftlint.yml) (Sources/ and Tests/ only). There is no Makefile lint target and Package.swift does not invoke it; CI runs:

```bash
brew install swiftlint   # once
swiftlint lint --strict --config .swiftlint.yml
```

Match existing style. Do not turn rules off to land a PR.

## ShellCheck and shfmt

CI runs [scripts/ci-shellcheck.sh](scripts/ci-shellcheck.sh) and [scripts/ci-shfmt.sh](scripts/ci-shfmt.sh) on `helper/*.sh`, `scripts/*.sh`, `uninstall.sh`, `helper/ntfs-rw-helper`, and `scripts/ntfsmount`.

```bash
brew install shellcheck shfmt   # once
./scripts/ci-shellcheck.sh
./scripts/ci-shfmt.sh
```

`shfmt -d -i 2`. Do not disable the job; format the script instead (`shfmt -w -i 2`).

## Markdown lint

CI lints `README.md` and `docs/*.md` with `markdownlint-cli2` ([.markdownlint-cli2.jsonc](.markdownlint-cli2.jsonc)). Line length is off; README HTML tables and mermaid fences are allowed.

```bash
npx markdownlint-cli2
```

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
- SIP stays enabled. Do not add csrutil commands. The app does not use a kext.
- Do not embed `sudo` or `osascript` elevation in the app. Helper install/uninstall uses `SMAppService` or Authorization Services.
- Do not silently clear the NTFS hibernation file (`hiberfile`).
- Format / ntfsfix / writable-confirm dialogs stay **Cancel-default**: Return must not confirm a destructive action.
