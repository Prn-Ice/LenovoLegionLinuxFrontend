# Legion Linux Frontend

A Linux desktop app for controlling Lenovo Legion laptops with [LenovoLegionLinux](https://github.com/johnfanv2/LenovoLegionLinux).

## Features

- Fan curve editor
- Power modes
- Battery conservation and rapid charging
- Fn-lock and touchpad controls; camera status
- Boot logo customization
- Discrete GPU monitoring
- [Keyboard lighting profiles for each power mode](docs/keyboard-automation.md)
- Keyboard lighting through Spectrum HID or OpenRGB
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

Running the app requires `legion_cli` in `PATH`. You can
[run tests without it](CONTRIBUTING.md#test-without-hardware).

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
