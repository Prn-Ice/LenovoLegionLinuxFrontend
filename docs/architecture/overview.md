# Architecture overview

The app uses Flutter on Linux. It reads hardware data through sysfs and D-Bus.
Privileged hardware changes go through the C++ `legion-control` service
(`io.github.prnice.LegionControl1`), which checks permissions with Polkit and
accepts only approved operations. Optional automation runs as the current user.

Keyboard lighting communicates with supported keyboards through HID, not
`legion-control`.

## Code layout

- `lib/core/services/` contains shared sysfs, D-Bus, and desktop service access.
- `lib/features/<feature>/` contains each feature's models, repositories, blocs,
  providers, and views.
- `lib/features/navigation/` connects pages to the application shell.
- `telemetry/` and `control/` contain native C++ D-Bus services and control
  command validation. Packaging files define service, bus, and Polkit setup.
- `test/` contains tests that run without hardware, including widget tests.

Repositories access services. Bloc/Cubit manages feature behavior. Riverpod
creates and disposes dependencies.

## How reads and changes work

**Reads:** service → repository → Bloc/Cubit state → UI.

**Changes:** UI → Bloc/Cubit → repository → `LegionControlClient` → native
service. The service checks and applies the change. The feature then reloads its
state or reports an error.

Older code uses `LegionFrontendBridgeService.runPrivilegedCommand` for queuing
and command history. `LegionControlClient` maps these commands to approved D-Bus
methods. Use `LegionControlClient` for new operations.

Opt-in [next-boot graphics requests](next-boot-graphics.md) also use the control
service. They save the requested mode for the next boot.

For contributor workflow and safe hardware testing, see
[Contributing](../../CONTRIBUTING.md) and the [model-support guide](../model-support.md).
See the [sysfs/CLI access audit](sysfs-vs-cli-access-audit.md) for each feature's
read and write methods.
