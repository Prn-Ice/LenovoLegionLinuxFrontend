# Tag releases

Pushing a `v*` tag runs `.github/workflows/release.yml`. It checks the version,
runs the full CI workflow on that commit, and creates a draft GitHub release
with the checked Ubuntu AppImage and its companions. Drafts retain the current
qualification notes while real hardware and desktop password-prompt checks
remain open.

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
journeys, and the AppImage build/acceptance VM. The draft job starts after every
check succeeds.

The release helper then verifies the tag version, app/source hashes, complete
helper inventory, and the VM evidence. The evidence must describe a clean
checkout of the tagged commit and identify the same release manifest.

The draft contains five assets:

- Ubuntu x86-64 `.AppImage`
- Matching source archive, including runtime source inputs and notices
- Build manifest
- Acceptance evidence archive
- `SHA256SUMS` covering all four files

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

This workflow packages the implemented Ubuntu AppImage target. Nix and Debian
release assets will join it when their package builds are implemented.

The workflow was checked with actionlint and offline fixture tests. The first
tag push will exercise GitHub's live draft/upload path.

See GitHub's [reusable workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows),
[artifact downloads](https://github.com/actions/download-artifact), and
[release CLI](https://cli.github.com/manual/gh_release_create) documentation.
