# Nix frontend

Build or launch the desktop app on x86_64 Linux:

```bash
nix build .#frontend
nix run .#frontend
```

The flake pins Flutter 3.47.9, Dart 3.13.7, Nixpkgs, and the pub.dev dependency
hashes. Nix downloads these inputs first, then builds the app in its offline
sandbox. The package contains the desktop launcher, icons, notices, and temporary
helper. Installing it enables no persistent Legion service.

On NixOS, add `inputs.legion.packages.x86_64-linux.frontend` to
`environment.systemPackages`, where `inputs.legion` is this repository's flake.
Use a pinned revision or release tag for your configuration.

## Hardware access

Install the Lenovo Legion driver and `legion_cli` on the host. Temporary helper
mode requires systemd, Polkit, and a desktop authentication agent. On NixOS,
install the CLI through `environment.systemPackages` so the helper can discover
it through the root-controlled system profile. A user profile cannot supply the
privileged backend.

Installed service remains the default. To use the bundled helper, choose
**Temporary helper** in Settings, close the app, and reopen it. Approval starts
a temporary systemd unit; exiting the app ends that unit. Keep the existing
[NixOS service module](../packaging/nixos/legion-telemetry.nix) enabled if you use
Installed service mode.

## Source and dependency updates

```bash
nix build .#frontend-source
ls result/*-source.tar.gz
```

The archive contains the project, hosted Dart dependency sources, their licenses,
and a manifest of immutable Nix source paths and pub.dev archive hashes. The
project's flake lock pins the native libraries and SDK obtained during rebuilding.
The archive's README explains rebuilding and the dependency copies.

After changing `pubspec.yaml` or `pubspec.lock`, refresh the JSON files used by
Nix's pure evaluator:

```bash
nix develop -c bash tool/update_nix_metadata.sh
nix build .#checks.x86_64-linux.nix-metadata
```

## Verification

```bash
nix build .#checks.x86_64-linux.frontend-package --print-build-logs
```

This disposable NixOS VM launches the installed desktop to its first Flutter
frame and tests the actual bundled helper with a synthetic CLI. It checks CLI
discovery, approval, write/readback/restore, cleanup, and the absence of installed
Legion services. The guest has no Legion driver. Hardware readback and desktop
password dialogs need separate testing.

CI runs analysis, unit tests, and native tests on every PR. Packaging, desktop
integration, and VM checks run when app, native, dependency, packaging, test,
tool, or workflow inputs change. Every push to main and release tag runs them.
Documentation-only PRs skip those heavier checks.
