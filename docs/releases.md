# Tag releases

Pushing a `v*` tag runs `.github/workflows/release.yml`. It checks the version,
checks the full CI suite on that commit, and creates a draft GitHub release
with the checked AppImage, Debian package, and their companions. Drafts retain
qualification notes while real hardware and desktop password-prompt checks
remain open.

## Deployment status: 17 November 2026

Nix, Debian, and AppImage packaging and automated acceptance pass on merged
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
- Keep the known-issue notes with the release. Exact upstream Alpine package
  revisions remain unverified; see the [runtime provenance limitation](appimage.md#runtime-inputs).
- Select the release version and commit, push a signed tag, verify the draft's
  uploaded files and checksums, then review it for publication. The live tag and
  upload path has not yet been exercised; no GitHub release exists.

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

## Push a tag

Tag a commit containing the release workflow and the intended version in
`pubspec.yaml`. Use `v` followed by the version before its build number:

| pubspec.yaml | Tag |
| --- | --- |
| `1.0.0+1` | `v1.0.0` |
| `1.1.0-rc.1+2` | `v1.1.0-rc.1` |

For the current version, when ready:

```bash
git tag -s v1.0.0 -m "v1.0.0"
git verify-tag v1.0.0
git push origin v1.0.0
```

A mismatched tag stops before the build. The workflow checks out the triggering
commit, including when main has advanced. Before creating the draft, it verifies
that the tag still resolves to the same commit on GitHub.

## What runs

The tag workflow calls the same CI workflow used for main and pull requests.
It first looks for a completed, successful main CI run with both package artifacts
for the exact tagged commit. If found, it downloads those artifacts and skips its
CI call. Otherwise it runs the full suite. PR results cannot supply a release.
See [CI result reuse and caching](ci.md) for the trust checks and retention limits.

The suite covers release-tool fixtures, Flutter analysis/tests and generated
sources, native tests, NixOS lifecycle/bootstrap VMs, Linux app journeys, Nix
frontend build/acceptance, AppImage acceptance (including Ubuntu helper checks),
and Debian installation/upgrade/removal on Ubuntu 22.04 and Debian 12. The draft
job starts after the suite passes or a qualifying main run is found.

The release helper then verifies the tag version, app/source hashes, complete
helper inventory, and the VM evidence. The evidence must describe a clean
checkout of the tagged commit and identify the same release manifest.

Run the helper with the Flutter SDK's Dart executable; no package resolution is
needed:

```bash
dart tool/release_workflow.dart check-tag v1.0.0
dart tool/release_workflow.dart prepare v1.0.0 build/release-inputs build/prepared-release
GITHUB_REPOSITORY=Prn-Ice/LenovoLegionLinuxFrontend dart tool/release_workflow.dart publish v1.0.0 build/prepared-release
```

Preparation reads `appimage-release`, `appimage-qualification`, `deb-release`,
`deb-ubuntu-qualification`, and `deb-debian-qualification` under
`build/release-inputs`. Publishing needs authenticated `gh` access and creates
or refreshes a draft; it never publishes that draft.

The draft contains nine assets:

- Ubuntu x86-64 `.AppImage`
- Matching source archive, including runtime source inputs and notices
- Build manifest
- Acceptance evidence archive
- Debian amd64 `.deb`, matching source archive, build manifest, and evidence from both VMs
- `SHA256SUMS` covering all eight files

The build jobs use read access. Only the final draft job receives repository
write access through the built-in `GITHUB_TOKEN`; it needs no extra secret.
Prerelease versions receive the GitHub prerelease flag.

## Review and reruns

Wait for the workflow to finish before editing or publishing its draft. Review
the files, checksums, and qualification notes on the repository's Releases page.
AppImage desktop instructions are in [the AppImage guide](appimage.md).

Rerunning the workflow refreshes the existing draft and replaces its generated
assets. Reruns refuse a tag that already has a published release. A changed tag,
missing evidence, or an altered artifact stops the draft update.

See [Debian installation](debian.md) for the `.deb` and its dependency baseline.
The [Nix frontend](nix.md) can be built directly from the release tag's flake.

The workflow was checked with actionlint and offline fixture tests. The first
tag push will exercise GitHub's live draft/upload path.

See GitHub's [reusable workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows),
[artifact downloads](https://github.com/actions/download-artifact), and
[release CLI](https://cli.github.com/manual/gh_release_create) documentation.
