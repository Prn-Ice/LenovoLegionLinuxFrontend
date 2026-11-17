# CI checks and caching

CI keeps analysis, generated-source checks, unit tests, and native tests on PRs.
The unit suite includes release-tool tests. The four VM-support shell suites run
in that same job. AppImage acceptance also runs the Ubuntu native-helper
qualification, so CI does not start another VM for that identical check.

## Which expensive checks run

`tool/ci_build_changes.sh` selects PR checks from changed paths, including both
sides of renames and deletions:

| Changed inputs | Selected checks |
| --- | --- |
| App code, assets, or Linux runner | Linux integration, Nix package, AppImage, Debian |
| Integration journeys or their runner script | Linux integration |
| Debian packaging or its build tools | Debian |
| AppImage package tool or acceptance runner | AppImage |
| Shared AppImage packaging files, including the container and SDK pin | AppImage, Debian, Nix package |
| Nix inputs | Nix package, lifecycle VMs, AppImage's NixOS acceptance |
| Shared package/source tools and license inputs | Nix package, AppImage, Debian |
| Native code, shared VM fixtures, workflows, or dependency locks | Every expensive check |
| Documentation, unit tests, or release tooling alone | None |

Unknown build-tool changes select every expensive check. Release tags select
every check. A newer PR run cancels an older run for the same PR. Merging a PR
does not start another CI run.

## Merge requirements

The public repository uses GitHub Free's branch protection for `main`:

- Require a PR before merging, without requiring another person's approval.
- Require the PR branch to be up to date with `main` and its checks to pass.
- Apply these requirements to administrators too; block force pushes and deletion.

Require all ten jobs in `ci.yml`, including the selector, package builds, and
acceptance jobs, `Conventional Commits`, and OSV's `pull-request / osv-scan`.
Accept check results only
from the GitHub Actions app. GitHub accepts jobs skipped by changed-path selection;
a failed selector or selected job blocks merging. Keep the required-check names
in branch protection in sync when adding or renaming jobs.

If another PR merges first, update the remaining PR branch and let its checks
run again before merging. This tests the new combination of changes, rather than
repeating checks after a merge. Direct pushes to `main` are blocked.

`conventional-commits.yml` checks PR titles on opening, reopening, edits, and
pushes. It also checks new non-merge commit subjects against the allowed types
in [Contributing](../CONTRIBUTING.md#make-a-change). It uses read-only permissions.
Squash-only merges use the PR title as their default subject; the maintainer
must preserve that format if editing the final message. GitHub rejected a native
`commit_message_pattern` ruleset for this repository, so enforcement uses a
required Actions check rather than a server-side commit-message rule.

## Retry failed jobs

Use GitHub's **Re-run failed jobs**, or:

```bash
gh run rerun RUN_ID --failed
```

GitHub preserves successful jobs and their outputs, then reruns failed jobs and
their dependents. Package builds and acceptance are separate jobs, so an
acceptance retry downloads the existing build from the same run. Unqualified
build artifacts last seven days; if they expire, rerun the build job too.
**Re-run all jobs** deliberately runs all jobs again.

Acceptance jobs retain the package and evidence together for releases. Artifact
downloads do not preserve execute permissions; AppImage acceptance restores its
executable bit before running it.

## Full release validation

The tag workflow always calls `ci.yml` for the tagged commit and runs every check.
Release preparation downloads the qualified AppImage and Debian packages from
that same workflow run, never from a PR or an earlier main run. It verifies the
tag, source/binary hashes, helper inventory, and acceptance evidence before
uploading and publishing the release.

OSV scans PRs and runs a full scan every Monday or when started manually. It does
not repeat the scan on merge. Weekly scans check for new vulnerability reports
that can affect unchanged dependencies.

## Download caches

- `subosito/flutter-action` caches the pinned SDK and pub downloads. Dependency
  resolution still enforces `pubspec.lock`; generated and compiled app files
  are not restored from this cache.
- Package jobs cache the Flutter archive and pinned AppImage runtime/source
  downloads. The download steps verify their expected SHA256 values after a
  cache restore and replace corrupt bytes before building.
- Ubuntu acceptance fetches the current official checksum list on every run
  and keys the cloud-image cache by that checksum. It verifies the cached image
  before booting a fresh overlay. VM state is never cached.

GitHub controls cache scope: PR merge-ref caches do not become main/tag caches.
Caches save downloads; a cache hit does not count as a passed check.
Nix still uses its configured upstream binary caches. We do not copy `/nix/store`
into an Actions cache or add a project binary-cache service. Debian images,
container layers, and container-local pub downloads are not cached here.

## Local checks

```bash
nix develop --command flutter test test/tool
nix develop --command flutter analyze
nix shell --inputs-from . nixpkgs#actionlint --command actionlint
bash test/tool/portable_distro_evidence_test.sh
```

Expect the selector fixtures, download-cache fixtures, analysis, workflow lint,
and evidence-retention checks to pass. Live cache restoration, release artifact
downloads, and merge enforcement need GitHub Actions runs; local fixtures do not
prove that integration.
