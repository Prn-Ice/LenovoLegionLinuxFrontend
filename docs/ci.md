# CI selection, caching, and result reuse

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
| Documentation, unit tests, or release-draft tooling alone | None |

Unknown build-tool changes select every expensive check. Main pushes and tag
CI select every check. A newer PR run cancels an older run for the same PR.

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

## Reuse main CI for a release

The tag workflow uses `tool/find_release_ci.dart` to look for a completed,
successful `ci.yml` push run on this repository's main branch at the exact tagged
SHA. Both package artifacts must still be nonempty and unexpired. The lookup
checks up to 20 matching runs and the first 100 artifacts per run; this workflow
produces fewer than 100 artifacts. A missed result costs a fresh CI run.

When a match exists, the release skips its CI call and downloads both qualified
packages from that run. Otherwise, including on API failure, it runs full CI.
Create the tag after main CI completes to get this reuse; an unfinished main run
does not qualify. Release preparation still verifies the tag, source/binary hashes,
helper inventory, and acceptance evidence. PR runs never supply releases.

This is the only cross-workflow result lookup. PR and main runs use GitHub's
ordinary execution and retry behavior. A merge normally creates a different SHA.
OSV scans remain fresh because new vulnerability reports can affect unchanged
dependencies.

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
and evidence-retention checks to pass. Live cache restoration and cross-workflow
downloads need GitHub Actions runs; local fixtures do not prove that integration.
