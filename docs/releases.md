# Tag releases

Pushing a `v*` tag runs `.github/workflows/release.yml`. It checks the version,
runs the full CI suite on that commit, and publishes a GitHub release with the
checked AppImage, Debian package, and their companions. Versions such as
`0.1.0-alpha.2` publish as prereleases for testing. Real-hardware and desktop
password-prompt checks remain open; see the [AppImage trial](appimage.md#desktop-trial).

## Deployment status: 17 November 2026

[v0.1.0-alpha.2](https://github.com/Prn-Ice/LenovoLegionLinuxFrontend/releases/tag/v0.1.0-alpha.2)
is published as a prerelease for testing. Its app version is `0.1.0-alpha.2+1`.
[Release CI 44139378824](https://github.com/Prn-Ice/LenovoLegionLinuxFrontend/actions/runs/44139378824)
passed on tagged commit `a702c7fa1b69e6507f72d96b92164889384c20ee`. All nine
assets downloaded, and all eight entries in `SHA256SUMS` passed. The earlier
`1.0.0+1` was a placeholder, not a stability claim; no `v1.0.0` tag was pushed.

The signed `v0.1.0-alpha.1` tag and its draft remain as evidence of the first
live workflow run. It reused passing main CI and uploaded all nine files, but
GitHub renamed the Debian filename's `~` to `.`. The downloaded package bytes
matched their digest; `sha256sum --check SHA256SUMS` failed because the listed
filename was missing. The draft was not published. Alpha.2 uses upload-safe
filenames, preserves Debian's internal prerelease version, and verifies remote
asset names, sizes, digests, and draft/prerelease flags after uploading.

Earlier Nix, Debian, and AppImage packaging and automated acceptance passed on merged
main `404980d9e00c4ef17271b87a7db93ca37ceca93f`:
[CI run 44094959984](https://github.com/Prn-Ice/LenovoLegionLinuxFrontend/actions/runs/44094959984).
All ten jobs passed, including Debian checks on Ubuntu 22.04 and Debian 12,
Ubuntu AppImage FUSE/extraction, and standard NixOS `appimage-run` acceptance.
The security scan also passed. PRs #9, #15, #4, and #17 are merged.

That run retains `appimage-ubuntu-22.04` (artifact `14335355363`) and
`debian-amd64` (artifact `14334586239`), with matching sources and VM evidence.
Use the manifests and `SHA256SUMS` inside those bundles to identify the files;
the historical hashes below describe an older candidate. A later code change
needs acceptance evidence for its own commit.

On 17 November, the user chose to continue deployment and defer crash research
unless a concrete cause and simple supported fix are available. The historical
[shutdown failure](linux-shutdown.md) remains a known issue, not a demonstrated
fix. It no longer blocks deployment work by itself. Standard package close
checks remain required; a failing candidate cannot supply release evidence.

Remaining work:

- Startup recovery is deferred: the corrected two-process test found that Hive
  removes another process's lock file after a failed open. See the
  [reproduction and resume condition](startup-storage.md) (`lllf-wzb`).
- Record the [desktop trial](appimage.md#desktop-trial) against the final candidate:
  password cancellation and retry, physical readback and restoration, helper
  cleanup, and numeric exit status. Record desktop/session and package hash.
- Check restored, maximized, and fullscreen window corners and the running-app
  icon on the target desktops. The user confirmed the corrected AppImage works;
  that confirmation did not enumerate every window state.
- Keep the known issues documented for testers. Exact upstream Alpine package
  revisions remain unverified; see the [runtime provenance limitation](appimage.md#runtime-inputs).

TCG/Nehalem rendering stalls, Dolphin previews, and the initial cursor warning
remain separate follow-ups. CI requires KVM; its passes do not qualify TCG.

## Historical official candidate: 16 November 2026

The artifacts from [CI run 43726942646](https://github.com/Prn-Ice/LenovoLegionLinuxFrontend/actions/runs/43726942646)
retain the earlier failure evidence. They identify
CI merge `e1c1d5392db90a78a46da43b9c45d9caf2672311`, whose second parent is
PR #9 head `77a189e`. Documentation updates do not change that artifact identity.

The [official Linux SDK release metadata](https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json)
identifies Flutter 3.50.0 as stable, with archive SHA256
`6ea2d806fd57269ae783e6788e2a81fc26eaad782f1e0d0ff38623bb765ff9f5`.
Both source companions record framework
`ab2912035e160d9cad6306df307576da6128ebdb` and engine
`371f77202a73e8dff57a8b3bff75bca55c090aee`. Both include the unchanged runner
with engine retention from `a3c9262`. No custom engine is included.
Both packages' `libflutter_linux_gtk.so` hashes match the release engine in the
checksum-verified official SDK archive:
`cb40d5867033badfa1a38072fab83f1c60ec1520c303a4810f49979f0ba5df04`.

| File | SHA256 |
| --- | --- |
| `legion-frontend-1.0.0+1-x86_64.AppImage` | `ae10838f03ee4318e33b9b88b702cb19d6f0fbdb98906ad799c03ac060d5afbe` |
| `legion-frontend-1.0.0+1-x86_64-source.tar.gz` | `a02d694ae8e8c780ca723ae62c528a7d8db2297915c9d757982c61eb5dd9ad07` |
| `legion-linux-frontend_1.0.0+1-1_amd64.deb` | `3b169c4d1fe8cb684c958363ded0a43b399b1dfed226e390ef023af06a85bae2` |
| `legion-frontend-1.0.0+1-amd64-source.tar.gz` | `321ec05b544d4977d0634fbcd088873d7a5669f07d5561fe6c3ed60686145162` |

GitHub artifacts `14167476683` (`appimage-ubuntu-22.04`) and `14167018271`
(`debian-amd64`) contain the packages, source companions, manifests, checksums,
and retained acceptance output. Local copies are under
`/tmp/opencode/ci-43726942646-appimage-artifact/appimage-release/` and
`/tmp/opencode/ci-43726942646-debian-artifact/deb-release/`. Package/source hashes,
complete bundle inventories, SDK revisions, and runner source were rechecked
without rebuilding or relaunching the apps. The retained AppImage acceptance
archives match that exact image; they passed Ubuntu FUSE/extraction and NixOS
standard `appimage-run`, including ten X11 and ten Wayland closes.

The Debian package failed Ubuntu normal close; Debian 12 did not run. The exact
package also failed the hosted core diagnostic linked in the
[shutdown record](linux-shutdown.md). This candidate was not qualified; newer
passing candidates do not erase its failure. On 16 November, the user reported
that this official AppImage works on their machine and confirmed that retry
works too. Hardware readback, restoration, helper cleanup, and numeric process
exit status were not explicitly reported. The [desktop trial](appimage.md#desktop-trial)
describes those remaining checks. This positive hardware result did not
resolve that candidate's Debian failure.

At the time of that trial, `build/legion-frontend.AppImage` pointed to the
user-tested `46b827e` build, which used official Flutter 3.47.9 and hashed to
`018ea3f01a17a2b629ca4e8bb7589b17bf176bc144320959c11cd37121911929`.
Check the actual target and checksum before using a local convenience link.

## Prepare a release and push its tag

From a clean checkout on a release branch, run:

```bash
nix run .#tag -- --prepare 0.1.0-alpha.3+1
```

This updates `pubspec.yaml` and regenerates the Nix metadata with
`tool/update_nix_metadata.sh`. Review the diff, sign and push the commit, and open
a PR targeting `main`. After the PR merges, check out the merged release commit
and push its tag as described below.

Tag a commit containing the release workflow and the intended version in
`pubspec.yaml`. Use `v` followed by the version before its build number:

| pubspec.yaml | Tag |
| --- | --- |
| `0.1.0-alpha.2+1` | `v0.1.0-alpha.2` |
| `1.1.0-rc.1+2` | `v1.1.0-rc.1` |

From a clean checkout of the release commit, create and verify its signed tag:

```bash
nix run .#tag
```

The app reads the committed `pubspec.yaml` and uses your Git signing settings.
Configure signing and verification as you would for `git tag -s` and
`git verify-tag` (SSH signing needs `gpg.ssh.allowedSignersFile`).

To create, verify, and push the tag to `origin`, run:

```bash
nix run .#tag -- --push
```

You can also use `--push` after creating the tag locally. An existing tag must
point to HEAD and pass signature verification; the app preserves its signed
object. A failed verification or push leaves the local tag available for retry.
Pushing the tag starts the release workflow below.

A mismatched tag stops before the build. The workflow checks out the triggering
commit, including when main has advanced. Before uploading and publishing, it verifies
that the tag still resolves to the same commit on GitHub.

## What runs

The tag workflow calls the same CI workflow used for pull requests, but always
runs the full suite for the exact tagged commit. It downloads package artifacts
from that same release run; PR results cannot supply a release.
See [CI checks and caching](ci.md).

The suite covers release-tool fixtures, Flutter analysis/tests and generated
sources, native tests, NixOS lifecycle/bootstrap VMs, Linux app journeys, Nix
frontend build/acceptance, AppImage acceptance (including Ubuntu helper checks),
and Debian installation/upgrade/removal on Ubuntu 22.04 and Debian 12. The publish
job starts only after the suite passes.

The release helper then verifies the tag version, app/source hashes, complete
helper inventory, and the VM evidence. The evidence must describe a clean
checkout of the tagged commit and identify the same release manifest.

Run the helper with the Flutter SDK's Dart executable; no package resolution is
needed:

```bash
dart tool/release_workflow.dart check-tag v0.1.0-alpha.2
dart tool/release_workflow.dart prepare v0.1.0-alpha.2 build/release-inputs build/prepared-release
GITHUB_REPOSITORY=Prn-Ice/LenovoLegionLinuxFrontend dart tool/release_workflow.dart publish v0.1.0-alpha.2 build/prepared-release
```

Preparation reads `appimage-release`, `appimage-qualification`, `deb-release`,
`deb-ubuntu-qualification`, and `deb-debian-qualification` under
`build/release-inputs`. Publishing needs authenticated `gh` access. It uploads
to a draft, verifies the remote filenames, sizes, digests, and prerelease flag,
then publishes and verifies the resulting release. Upload verification must
pass before publication.

The release contains nine assets:

- Ubuntu x86-64 `.AppImage`
- Matching source archive, including runtime source inputs and notices
- Build manifest
- Acceptance evidence archive
- Debian amd64 `.deb`, matching source archive, build manifest, and evidence from both VMs
- `SHA256SUMS` covering all eight files

The build jobs use read access. Only the final publish job receives repository
write access through the built-in `GITHUB_TOKEN`; it needs no extra secret.
Prerelease versions receive the GitHub prerelease flag and are not marked Latest.

## Release notes

Notes group commits under Breaking changes, Features, Fixes, Improvements,
Documentation, and Maintenance. Empty sections are omitted. Each entry contains
the description, optional scope, and a commit link; the notes end with a full
changelog link. Conventional prefixes such as `fix:` become section headings.
Older subjects without a prefix appear under Maintenance.

The range starts after the nearest preceding version tag reachable from the
release commit. Merge messages are omitted; the commits they introduced are
included. The first tag lists its full history. Preparation requires a full
checkout, and later commits on main do not enter an older tag's notes.
Hardware requirements and known issues live in the installation guides.

For example:

```markdown
## What changed

### Features

- fans: add a quiet preset (commit link)

### Fixes

- preserve the curve after a failed write (commit link)

Full changelog
```

Keep entries short and describe the effect on the app or its maintenance.
The [commit conventions](../CONTRIBUTING.md#make-a-change) keep future notes
consistent. Repository settings require the `Conventional Commits` check, use
squash-only merges, and select `PR_TITLE` for the default squash subject.
Configure these server settings when creating a new repository from this source.

## Review and reruns

The workflow publishes after its checks pass. Download the release files and run
`sha256sum --check SHA256SUMS`; every listed file should report `OK`.
AppImage desktop instructions are in [the AppImage guide](appimage.md).

After an upload failure, rerunning the workflow refreshes the draft, verifies its
assets, and publishes it. Reruns refuse a tag that already has a published release.
A changed tag, missing evidence, or an altered artifact stops publication.

See [Debian installation](debian.md) for the `.deb` and its dependency baseline.
The [Nix frontend](nix.md) can be built directly from the release tag's flake.

The alpha.1 tag exposed the filename normalization described above. Alpha.2
passed the live download and checksum checks and was published from its draft
at the user's request. Automatic publication will first run on a subsequent tag.

See GitHub's [reusable workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows),
[artifact downloads](https://github.com/actions/download-artifact), and
[release CLI](https://cli.github.com/manual/gh_release_create) documentation.
