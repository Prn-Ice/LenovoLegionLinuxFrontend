# Legion Linux Frontend

A Flutter-based desktop frontend for [LenovoLegionLinux](https://github.com/johnfanv2/LenovoLegionLinux) - the open-source Linux kernel module and tooling for Lenovo Legion laptops.

## Features

- Fan curve editor
- Power profile / platform profile switching
- Battery conservation and rapid charging
- Fn-lock and touchpad controls; camera status
- Boot logo customization
- Discrete GPU monitoring
- Automation (run external programs on profile change)
- Keyboard lighting (native Spectrum HID and OpenRGB)
- Real-time dashboard

## Requirements

For development and hardware-free tests, install Flutter (stable; this project
currently requires Flutter 3.47.9 or newer) and the Linux desktop build tools
required by Flutter: CMake, Ninja, a C/C++ compiler, pkg-config, GTK 3
development headers, and C++ standard-library development files. Native service
checks additionally need GLib/GIO development files; building the control service
also needs Polkit development files. Package names vary by distribution. See
[Contributing](CONTRIBUTING.md) for commands and a hardware-free workflow.

To use hardware features, separately install and configure the supported
`legion_linux` module and `legion_cli` backend. Privileged writes require the
`legion-control` service, its system D-Bus policy and Polkit action, plus a
desktop Polkit authentication agent. These are not required to build or run the
test suite. NVIDIA drivers are optional for dGPU features.

On NixOS, import `packaging/nixos/legion-telemetry.nix` and enable the control service:

```nix
security.polkit.enable = true;
services.legionControl = {
  enable = true;
  backendPackage = pkgs.lenovo-legion;
};
```

## Running

The live application requires `legion_cli` in `PATH`, even when hardware features
are unavailable. Use the hardware-free tests in [Contributing](CONTRIBUTING.md)
for development without the backend.

```bash
flutter run -d linux
```

Or build a release binary:

```bash
flutter build linux --release
```

## Development

See [Contributing](CONTRIBUTING.md) for portable setup, testing, and the
[model-support guide](docs/model-support.md). Optional Nix users may set
`LLLF_DEV_FLAKE` to their own Flutter/Linux development flake before allowing
direnv. See [dependency notes](docs/dependencies.md) for retained constraints.

```bash
flutter test
flutter analyze
```

## Architecture

Read operations use direct sysfs file reads or the read-only telemetry D-Bus service. Privileged writes use the typed `io.github.prnice.LegionControl1` system-bus API. That root service accepts only allow-listed operations, asks Polkit to authorize the frontend's D-Bus connection, and invokes fixed `legion_cli` or `systemctl` argument vectors without a shell. Dart never writes sysfs directly and never launches a privilege-elevation helper.

See [the architecture overview](docs/architecture/overview.md) for the main
boundaries. Report problems or propose changes through GitHub issues and pull
requests.

## License

Legion Linux Frontend is free software: you may redistribute it and/or modify
it under the GNU General Public License as published by the Free Software
Foundation, either version 2 of the License, or (at your option) any later
version (`GPL-2.0-or-later`). It is distributed WITHOUT ANY WARRANTY, including
the implied warranties of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See [LICENSE](LICENSE) for the full terms and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for OpenRGB attribution,
and separately licensed materials.
