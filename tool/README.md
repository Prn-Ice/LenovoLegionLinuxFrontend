# Project Tooling

Scripts and Dart utilities in this directory support packaging, CI checks, and
hardware diagnostics.

## Subdirectories

- [`packaging/`](packaging/) — Release source archives, AppImage and Debian
  builds, license-notice bundling, Nix metadata updates, and release tagging.
- [`ci/`](ci/) — Change-based CI selection, commit checks, Flutter archive
  caching, Linux journey runners, and distro/VM qualification harnesses.
- [`diagnostics/`](diagnostics/) — Hardware probes and TTY scripts for graphics,
  keyboard lighting, sleep events, and shutdown diagnostics.

For Dart scripting conventions, see [Dart scripting](../docs/dart-scripting.md).
For CI and release workflows, see [CI](../docs/ci.md) and
[releases](../docs/releases.md).
