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

- [Contributor setup and tests](CONTRIBUTING.md)
- [Adding model support](docs/model-support.md)
- [Project documentation](docs/README.md)

```bash
flutter test
flutter analyze
```

## Architecture

Read operations use direct sysfs file reads or the read-only telemetry D-Bus service. Privileged writes use the typed `io.github.prnice.LegionControl1` system-bus API. That root service accepts only allow-listed operations, asks Polkit to authorize the frontend's D-Bus connection, and invokes fixed `legion_cli` or `systemctl` argument vectors without a shell. Dart never writes sysfs directly and never launches a privilege-elevation helper.

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
