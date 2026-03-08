# Legion Linux Frontend

A Flutter-based desktop frontend for [LenovoLegionLinux](https://github.com/johnfanv2/LenovoLegionLinux) - the open-source Linux kernel module and tooling for Lenovo Legion laptops.

## Features

- Fan curve editor
- Power profile / platform profile switching
- Battery conservation and rapid charging
- Fn-lock, touchpad, camera toggles
- Boot logo customization
- Discrete GPU monitoring and deactivation
- Automation (run external programs on profile change)
- Display lighting (LampArray)
- Real-time dashboard

## Requirements

- `legion_linux` kernel module installed (provides sysfs interface)
- `legion_cli` installed and in PATH (provides privileged write access via polkit)
- NVIDIA driver (optional, for dGPU features)

## Running

```bash
flutter run -d linux
```

Or build a release binary:

```bash
flutter build linux --release
```

## Development

```bash
flutter test
flutter analyze
```

## Architecture

The frontend communicates with the backend exclusively through the system-installed `legion_cli` binary. No direct sysfs writes from Dart - all privileged operations go through `pkexec legion_cli <subcommand>`. Read operations use direct sysfs file reads via `dart:io`.

See `docs/architecture/` for detailed documentation.
