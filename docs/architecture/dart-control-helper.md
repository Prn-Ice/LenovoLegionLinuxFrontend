# Dart control helper

The portable control helper now implements typed hardware requests in Dart.
The native starter still obtains administrator approval, seals the approved
executable, stages its embedded runtime in a root-owned directory, and arranges
cleanup through systemd. The app uses its existing launch command and D-Bus API.
The installed system service remains native.

## Code and ownership

- `control/dart/run_control_helper.dart` checks the app's inherited process
  handles, qualifies the installed CLI, announces the private endpoint, and ends
  the session when the app exits.
- `peer_server.dart` uses libsystemd's private D-Bus server. Linux socket
  credentials must match the approved app's process and user IDs before
  authentication begins.
- `control_dispatcher.dart` checks authorization and typed arguments, creates
  private payload files, maps backend-specific exit codes, and waits for cleanup.
- `managed_command.dart` starts each CLI command in a systemd service. Each
  operation owns its bus connection and unit reference. Completion requires an
  empty cgroup and drained output; a shared file lock excludes competing helpers.
- `systemd_bus.dart` binds libsystemd's asynchronous client API. libsystemd
  handles message encoding, descriptor transfer, authentication, and deadlines.
  The Dart `dbus` package supplies value types and the helper's identity
  connection, which carries no descriptors.
- `linux_resources.dart` checks trusted executable paths and pinned processes.
  `unix_descriptor.dart` transfers a duplicate descriptor into Dart's public
  socket API without reopening the file or losing its lock ownership.

### Why both bus connections use libsystemd

The resolved `dbus` 0.8.0 server lacks a public peer-authorization hook and
private application-object dispatch. Its Unix-FD writer also omits the
four-byte alignment required for `h` values. A `StartTransientUnit` request
containing descriptor properties caused a real private `dbus-daemon` to
disconnect the client. Its in-process Dart server did not reveal that failure.

The helper therefore uses the already-bundled libsystemd API for its private
server and managed-command connections. It does not patch the package or
implement a D-Bus wire encoder.

## Build and verification

The standard build compiles the helper automatically:

```sh
nix develop --command flutter build linux --release
```

`tool/build_dart_helper_bundle.dart` compiles an AOT snapshot, copies the standard
Dart runtime and its loader, resolves libsystemd's library dependencies, removes
build-machine search paths, and embeds the files in the native starter.
Conflicting libraries with the same filename stop the build. The generated
manifest records filenames; provenance records the original files and hashes.

Run the hardware-free checks:

```sh
nix develop --command flutter test test/control/dart
nix build .#checks.x86_64-linux.portable-bootstrap
```

The Dart tests use local sockets, a private bus daemon, and a native fake systemd
service. They check identity, typed dispatch, payload permissions, output
draining, cancellation, owner loss, cgroup retention, and competing locks.
The VM check runs the production helper against guest systemd and Polkit with a
synthetic CLI. Those checks do not establish real hardware compatibility or
desktop password-prompt behavior.

The migration remains in draft until the normal AppImage launch, Ubuntu
acceptance, desktop authentication, and laptop write/readback checks pass.

On 19 November 2026, the full Flutter suite passed 1,012 tests with 32 skipped,
analysis passed, and the standard Linux release build succeeded. The production
NixOS VM check passed typed writes/readback, payloads, backend exit mapping,
timeouts, output floods, detached descendants, cancellation, helper crashes,
lock retention, startup rejection, approval denial, and cleanup. The separate
bundled-startup prototype regression also passed.
