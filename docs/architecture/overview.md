# Architecture overview

The frontend is a Linux Flutter application. Most hardware reads use unprivileged
sysfs or D-Bus access. Privileged writes use the typed
`io.github.prnice.LegionControl1` system-bus API. Its native C++ service
authorizes the frontend with Polkit, validates operations against an allow-list,
and invokes fixed backend commands. Dart does not write sysfs or launch a
privilege-elevation helper. Optional desktop automation runs as the user.

The keyboard lighting feature also has a native HID boundary: it communicates
with supported keyboard devices through HID rather than the privileged control
service. Device identity, protocol, layout, and calibration must be backed by
testing; an unknown device is not implicitly supported.

## Code boundaries

- `lib/core/services/` contains shared sysfs, D-Bus, and desktop service access.
- `lib/features/<feature>/` groups feature models, repositories, Bloc/Cubit
  behavior, providers, and views. Not every feature needs every directory.
- `lib/features/navigation/` connects pages to the application shell.
- `telemetry/` and `control/` contain native C++ D-Bus services and control
  command validation. Packaging files define service, bus, and Polkit setup.
- `test/` contains hardware-free tests using fakes, mocks, and filesystem
  fixtures. Some tests cover widgets and rendered states as well.

Keep UI behavior in the existing feature patterns. Repositories isolate external
I/O; Bloc/Cubit handles feature behavior; Riverpod supplies dependencies and
lifetime. Add layers only when they clarify a responsibility or boundary.

## Following a request

For reads, a feature repository obtains current values from a service and turns
them into feature state; the UI watches that state. For writes, a user action
passes through the feature behavior and repository to a typed control-client
operation. The native service validates and performs the operation, and the
feature refreshes state or reports failure. Readable state does not by itself
prove that a write is supported.

Legacy callers use `LegionFrontendBridgeService.runPrivilegedCommand` for
queuing and command history. Its CLI-shaped vocabulary is mapped by
`LegionControlClient` to typed D-Bus methods; it is not an arbitrary command
execution interface. New operations should use the typed client contract.

Opt-in [next-boot graphics requests](next-boot-graphics.md) also use the control
service. They save a request for a guarded boot service rather than switching
graphics immediately.

For contributor workflow and safe hardware testing, see
[Contributing](../../CONTRIBUTING.md) and the [model-support guide](../model-support.md).
The [sysfs/CLI access audit](sysfs-vs-cli-access-audit.md) records feature-specific
access paths.
