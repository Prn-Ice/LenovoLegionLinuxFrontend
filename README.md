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
- Display lighting (LampArray)
- Real-time dashboard

## Requirements

- `legion_linux` kernel module installed (provides sysfs interface)
- `legion_cli` installed (the privileged service uses its validated hardware operations)
- `legion-control.service`, its D-Bus policy, and its Polkit action installed
- A desktop Polkit authentication agent
- NVIDIA driver (optional, for dGPU features)

On NixOS, import `packaging/nixos/legion-telemetry.nix` and enable the control service:

```nix
security.polkit.enable = true;
services.legionControl = {
  enable = true;
  backendPackage = pkgs.lenovo-legion;
};
```

## Running

```bash
flutter run -d linux
```

Or build a release binary:

```bash
flutter build linux --release
```

## Development

Use Flutter **3.47.9** or newer on the stable channel. On this machine, `.envrc`
loads `/home/prnice/Projects/personal/nix_flakes/flutter_flake#linux`; there is no flake
in this repository. See [dependency notes](docs/dependencies.md) for SDK updates,
retained package constraints, and verification commands, and
[Contributing](CONTRIBUTING.md) for setup and code patterns.

```bash
flutter test
flutter analyze
```

## Architecture

Read operations use direct sysfs file reads or the read-only telemetry D-Bus service. Privileged writes use the typed `io.github.prnice.LegionControl1` system-bus API. That root service accepts only allow-listed operations, asks Polkit to authorize the frontend's D-Bus connection, and invokes fixed `legion_cli` or `systemctl` argument vectors without a shell. Dart never writes sysfs directly and never launches a privilege-elevation helper.

See `docs/architecture/` for detailed documentation.
