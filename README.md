# Legion Linux Frontend

A Linux desktop app for controlling Lenovo Legion laptops with [LenovoLegionLinux](https://github.com/johnfanv2/LenovoLegionLinux).

**In development, with only one physical device used for development and testing:**
the project owner's **Legion Slim 7 16APH8 (82Y4, BIOS M1CN48WW)**. Not every
feature has been verified even on that laptop. Other models and BIOS versions
have not been tested. See [model support and recorded checks](docs/model-support.md).

## Features and readiness

Status checked on **2026-11-04**. “Implemented” means the app has the feature,
not that every hardware path is verified. We do not yet claim any feature is
complete across Lenovo Legion models.

| Feature | Current state | Remaining limits |
| --- | --- | --- |
| Fan curve editor | Editor, presets, and hardware-write path implemented | Correct curve reporting and write/readback validation still need driver work on the test device. Fan RPM readings have been checked separately. |
| Power modes | Mode selection and supported power-limit controls implemented | A controlled CPU PL1 write/readback/restore passed on the test device; other limits need validation. Verified factory-default restoration is not ready. |
| Battery conservation and rapid charging | Both controls implemented; conservation on/off write and readback verified on the test device | Rapid-charging writes still need hardware verification. The Battery page can briefly show stale conservation state after a Dashboard change; use Refresh. |
| Fn-lock and touchpad controls; camera status | Controls and read-only camera status implemented | Fn-lock and touchpad writes still need recorded hardware checks. The camera status file is absent on the test device; camera control is not supported. |
| Boot logo customization | Image upload and restore paths implemented | Applying a logo, restoring it, and checking the next boot still need recorded hardware verification. |
| Discrete GPU monitoring | NVIDIA runtime state, compute-process list, and graphics-mode status implemented | Graphics switching is still being validated; Hybrid Auto is intentionally unavailable as a desktop action. Process killing and PCI restart are not supported by the control service. |
| [Keyboard lighting profiles for each power mode](docs/keyboard-automation.md) | Saved profiles and automatic mode-based switching implemented | The app must stay open. Native end-to-end persistence/restart checks and visual polish remain. |
| Keyboard lighting through Spectrum HID or OpenRGB | Both backends implemented | Native Spectrum currently targets USB `048d:c987` with the Gen 7/8 protocol. Other keyboards need device-specific verification; OpenRGB depends on its device support and setup. |
| Real-time dashboard | Periodically refreshed telemetry and quick controls implemented | Available readings depend on the driver and hardware. Read-only fan, power, and battery checks exist for the test device, not a multi-model test matrix. |

See the **[public backlog](BACKLOG.md)** for work in progress, known gaps, and
ways to help.

## Requirements

### Build and test

- Flutter stable 3.47.9 or newer
- CMake, Ninja, a C/C++ compiler, and pkg-config
- GTK 3 and C++ standard-library development files
- GLib/GIO development files for native services
- Polkit development files for the control service

See [Contributing](CONTRIBUTING.md) for installation commands.

### Hardware features

- Supported `legion_linux` kernel module
- `legion_cli` backend in `PATH`
- `legion-control` service with its D-Bus policy and Polkit action
- Desktop Polkit authentication agent
- NVIDIA drivers for NVIDIA dGPU features

On NixOS, import `packaging/nixos/legion-telemetry.nix` and enable the control service:

```nix
security.polkit.enable = true;
services.legionControl = {
  enable = true;
  backendPackage = pkgs.lenovo-legion;
};
```

## Running

Running the app requires `legion_cli` in `PATH`. You can
[run tests without it](CONTRIBUTING.md#test-without-hardware).

```bash
flutter run -d linux
```

Or build a release binary:

```bash
flutter build linux --release
```

To build the binary, add its resolved notices, and create a matching source
companion in one command (the worktree must be clean):

```bash
tool/package_release.sh --output build/release/legion-frontend-source.tar.gz
```

The command resolves packages with `--enforce-lockfile`, records their contents,
then builds with `--no-pub`. It rejects source changes during the build. The
archive contains tracked application source and the resolved runtime dependency
sources, including local package edits and `handy_window/linux/libhandy`.
`SOURCE-MANIFEST.json` records the commit, lockfile checksum, bundle checksums,
package contents, SDK-reported Flutter framework/engine versions, and (for a
Nix-installed SDK) the public source archive URL/ref/hash, derivation IDs, and
patch identifiers/content hashes. `REBUILD.md` and
`dependency-overrides.yaml` explain how to rebuild using the archived packages.

Application source follows `.gitattributes`: private `.beads` and `.env` files,
machine-local `.agent` links, and inspiration screenshots are excluded.
Dependency-root `.git`, `.beads`,
`.dart_tool`, `build`, `coverage`, `.env`, and `.env.*` are excluded; nested build
directories, `.envrc`, file modes, and internal symlinks are retained. Links
escaping a dependency root stop packaging.

Flutter SDK source is identified by its reported version and revisions rather
than included. For the tested Nix SDK, the manifest also records the exact
distributor archive ref and Nix content hash; the archive hash identifies bytes,
not a Git commit. Distributor builds can report a placeholder framework revision
(the tested Nix SDK does), so the framework Git commit remains unknown. If Nix
derivations have been garbage-collected, or the SDK is not Nix-installed,
provenance is marked unavailable rather than inferred; obtain SDK source
separately in that case.
Host libraries are obtained separately; downstream packages must add source and
notices for any extra libraries they redistribute. Publish the source companion
alongside the binary from `build/linux/x64/release/bundle`.

## Development

- [Contributor setup and tests](CONTRIBUTING.md)
- [Adding model support](docs/model-support.md)
- [Project documentation](docs/README.md)

```bash
flutter test
flutter analyze
```

## Architecture

The app reads hardware data through sysfs and D-Bus. Privileged changes go through
the `legion-control` service, which checks permissions with Polkit.

See the [architecture overview](docs/architecture/overview.md).

## License

Legion Linux Frontend is free software: you may redistribute it and/or modify
it under the GNU General Public License as published by the Free Software
Foundation, either version 2 of the License, or (at your option) any later
version (`GPL-2.0-or-later`). It is distributed WITHOUT ANY WARRANTY, including
the implied warranties of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See [LICENSE](LICENSE) for the full terms and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for OpenRGB attribution
and separately licensed materials.
