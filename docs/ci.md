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
workflows select every check, then look for reusable successes. No required
package acceptance was moved until after merge. A newer PR run cancels an older
run for the same PR. Main and tag CI runs for the same SHA share a concurrency
group, so a tag waits for an active main run before checking its results.

## Reusing passed checks and artifacts

Each successful job uploads a small `ci-pass-v1-CHECK-SHA` artifact. Its name
records the exact checked-out commit, including the synthetic merge commit on a
PR. `tool/ci_reuse.dart` uses GitHub's Actions API to find these markers and verify:

- The source workflow is this repository's CI on main, its tag workflow, or CI
  for the same open PR and head commit. Fork results are not reused.
- Main/tag results match the checkout SHA. PR markers match the merge SHA; a
  passed PR head is not a passed merge commit.
- The matching job succeeded, and uploaded the marker during that successful
  attempt. Failed, cancelled, and skipped jobs do not supply reusable results.
- Package jobs still have a nonempty, unexpired artifact uploaded during that
  same successful attempt, not a replacement from a later failed rerun.

Successful jobs can be reused even when another job in the source run failed.
The current run's summary links each reused result. Missing markers, expired
artifacts, unknown source workflows, and API failures cause checks to run again.
Markers expire after 90 days or the repository's shorter retention limit.
Deleting a check's success markers in GitHub forces that check to run again.

The tag workflow downloads AppImage and Debian artifacts from the selected run
IDs; the packages may come from different runs. It still validates the tag,
source and binary hashes, helper inventory, and acceptance evidence before
updating a draft. It never promotes PR artifacts into a release.

Package builds and acceptance are separate jobs. A passed build can supply an
acceptance retry without rebuilding. Unqualified build artifacts last seven days.
Acceptance jobs retain their complete package and evidence together, so release
reuse does not depend on those temporary build artifacts. This duplicates package
storage briefly, but avoids rebuilding after a VM-only failure. Artifact downloads
do not preserve execute permissions; the AppImage job restores its executable bit.

SHA matching is deliberate: a merge or squash normally creates a different
commit, even when its tree resembles the PR. We do not equate those commits.
OSV scans also remain fresh: new vulnerability reports can affect unchanged
dependencies, so a previous scan is not reused as a security result.

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
Caches save downloads; only verified successful-job markers can skip checks.
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
