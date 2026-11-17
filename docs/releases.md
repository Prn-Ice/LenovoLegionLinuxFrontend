# Tag releases

Pushing a `v*` tag runs `.github/workflows/release.yml`. It checks the version,
runs the full CI workflow on that commit, and creates a draft GitHub release
with the checked AppImage, Debian package, and their companions. Drafts retain
qualification notes while real hardware and desktop password-prompt checks
remain open.

The Flutter 3.50 upgrade has an unresolved [Linux shutdown failure](linux-shutdown.md).
Its package acceptance is incomplete; a tag build will stop if its close checks
fail. The workflow is configured, but this candidate is not qualified for release.

## Retained official candidate: 16 November 2026

Use the existing artifacts from [CI run 43726942646](https://github.com/Prn-Ice/LenovoLegionLinuxFrontend/actions/runs/43726942646)
for the remaining hardware checks; no identical rebuild is needed. They identify
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
[shutdown record](linux-shutdown.md). Keep PR #9 as a draft: no merge, tag, or
release while that gate remains unresolved. On 16 November, the user reported
that this official AppImage works on their machine and confirmed that retry
works too. Hardware readback, restoration, helper cleanup, and numeric process
exit status were not explicitly reported. The [desktop trial](appimage.md#desktop-trial)
describes those remaining checks. This positive hardware result does not
resolve the separate Debian CI failure.

The convenience link `build/legion-frontend.AppImage` still points to the
user-tested `46b827e` build, which used official Flutter 3.47.9. Its current
target hashes to `018ea3f01a17a2b629ca4e8bb7589b17bf176bc144320959c11cd37121911929`.
Do not replace that link without approval.

## Push a tag

Tag a commit containing the release workflow and the intended version in
`pubspec.yaml`. Use `v` followed by the version before its build number:

| pubspec.yaml | Tag |
| --- | --- |
| `1.0.0+1` | `v1.0.0` |
| `1.1.0-rc.1+2` | `v1.1.0-rc.1` |

For the current version, when ready:

```bash
git tag -a v1.0.0 -m "v1.0.0"
git push origin v1.0.0
```

A mismatched tag stops before the build. The workflow checks out the triggering
commit, including when main has advanced. Before creating the draft, it verifies
that the tag still resolves to the same commit on GitHub.

## What runs

The tag workflow calls the same CI workflow used for main and pull requests:
release-tool fixtures, Flutter analysis/tests and generated-source checks,
native tests, NixOS lifecycle/bootstrap VMs, Ubuntu helper checks, Linux app
journeys, Nix frontend build/acceptance, AppImage acceptance, and Debian package
installation/upgrade/removal on Ubuntu 22.04 and Debian 12. The draft job starts
after every check succeeds.

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
