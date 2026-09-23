# Guidance for coding agents

Read this first. [CONTRIBUTING.md](CONTRIBUTING.md) links to the organization-wide
contribution policy.

## Branch and PR rules

- PRs target `main`, the default and release branch. Branch from current
  `origin/main` and use one branch per issue.
- Keep each PR to one independently reviewable outcome. Up to 500 changed lines
  needs no size justification; 501-1,000 needs a cohesion explanation and
  review order; above 1,000 needs a split or maintainer-approved exception.
  Measure additions plus deletions against the target branch's merge base and
  follow the full policy in the
  [developer guide](https://github.com/WLAN-Pi/developers/blob/main/CONTRIBUTING.md#pr-size-and-scope).
- Do not mix moves, formatting, generated output, or package artifacts with
  behavioral changes.
- Documentation-only and CI-only changes do not update `debian/changelog`.
  Changing it creates a release when the change reaches `main`.

## Repository model

- This Debian package provides shared shell utilities, systemd units, udev and
  system configuration, and files consumed by other WLAN Pi packages.
- Installed commands under `usr/bin/` are generally symlinks to scripts under
  `opt/wlanpi-common/`. Change the implementation, not the symlink.
- Files under `debian/` control package installation, service lifecycle,
  dependencies, and release behavior. Treat maintainer scripts and root-run
  services as security boundaries.
- Preserve behavior across supported WLAN Pi models. Hardware-specific logic
  must remain conditional on detected model or hardware identity.

## Before you write

- Search existing scripts and callers before adding a helper or command. Fix a
  shared root cause once rather than guarding each caller.
- Follow the existing shell and packaging style. Prefer standard Linux tools
  and existing package dependencies; do not add a dependency for a small shell
  operation.
- Keep runtime data out of predictable shared `/tmp` paths. Root services use a
  private directory under `/run`, secure temporary files, and atomic rename
  when publishing data.
- Do not add compatibility code without a concrete persisted or external
  consumer. Ask before changing a command's output or exit status because FPMS
  and other packages may consume it.

## Tests and lint

Run the tests that cover the changed component. Repository-level regression
checks live in `tests/`; component tests live in
`opt/wlanpi-common/tests/`. Add one focused regression check for non-trivial
logic.

Run shellcheck over the same tracked files as CI:

```bash
{ git ls-files '*.sh'
  git ls-files -s | awk '$1 == "100755" {print $4}' | xargs -r grep -l '^#!.*sh'
} | sort -u | xargs -r shellcheck -S warning
```

Run `actionlint` after changing a workflow. CI runs both checks through
`.github/workflows/lint.yml`, except for documentation-only changes.

## Packaging and releases

- Build package-content changes before merge. CI runs an arm64 Trixie `sbuild`
  when a PR changes `debian/**`; a green lint job alone does not prove the
  package builds.
- Do not commit generated `.deb`, `.buildinfo`, or `.changes` files.
- Keep `debian/control`, install manifests, maintainer scripts, and systemd
  lifecycle behavior consistent. Verify installed paths and ownership from the
  built package, not only from the source tree.
- A push to `main` that changes `debian/changelog` deploys the package to
  Packagecloud. Do not bump the version until the candidate is tested and ready
  to publish.

## Device validation

Shell tests cannot model boot ordering, permissions, networking, GPIO, PCIe,
USB modes, radio drivers, or interactions with consuming services. For changes
to those paths:

1. Build and install the candidate package on representative hardware before
   committing the release change.
2. Exercise the changed behavior and its failure path.
3. Reboot when startup, kernel, udev, or systemd behavior changes.
4. Confirm service health, permissions, logs, and idempotence after the reboot.
5. Test each affected model or hardware family; do not infer one platform from
   another.

Do not run disruptive radio, network, pairing, shutdown, or configuration tests
without explicit approval from the device owner.

## Cost and scope

- Make the smallest change that fixes the root cause. Delete over add; boring
  over clever.
- Do not add speculative abstractions, configuration for fixed values, or a
  helper with one caller.
- Preserve unrelated worktree changes. Never reset or rewrite changes you did
  not make.
- Verify the relevant shell tests, lint, package build, and hardware behavior
  before committing. Record exact validation in the PR description.
