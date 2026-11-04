# Portable control and release formats

## Decision

Nix, Debian packages, and AppImage are first-class targets for the first release.
The AppImage goal is: install the supported driver and CLI, download the app,
open it, and authorize interactive hardware changes without installing our
system service.

The VM experiment now connects approved administrator startup to the real typed
control API with a synthetic CLI. Backend process containment and shared write
locking are implemented. Production desktop integration and release packages
remain to be implemented. See the [public backlog](../../BACKLOG.md).

## Installation experience

The intended release experience is:

| Format | Desktop app | Hardware control |
| --- | --- | --- |
| NixOS | Nix package | NixOS module installs and configures the system service |
| Debian | Desktop package | Service package supplies systemd, D-Bus, and Polkit integration |
| AppImage | Download and run | Bundled helper runs for the authorized app session |

Nix on another distribution can supply the desktop package. Driver setup and
installed-service or portable-helper integration need testing on that host.

The AppImage runs the UI as the current user. Readable sysfs data stays
unprivileged. When a write needs authorization, the intended flow is:

1. Explain that administrator access lasts for this app session.
2. Ask the host's Polkit agent to authorize the fixed control helper.
3. Connect this app instance to that helper over a private D-Bus connection.
4. Send the existing typed `LegionControl1` operations.
5. End the helper and its backend processes when the connection ends.

The installed service should be used when available and compatible. Select the
connection mode before writes. A denied request, incompatible service, or failed
backend command must not trigger a second privilege mechanism automatically.

Boot-time graphics reconciliation requires persistent system integration.
Optional power telemetry and direct keyboard HID access also need explicit
support decisions; the control prototype does not supply those permissions.

## Shared control implementation

`LegionControlClient` keeps its typed operations. The private connection carries
the same D-Bus interface, object path, argument types, and errors as the installed
service. The C++ command validation and dispatch remain shared.

Installed mode keeps its system-bus policy and per-connection Polkit approval.
Portable mode needs a separately reviewed bootstrap that establishes approval
before exporting operations to its one peer. It must never expose a method for
running arbitrary commands or accepting an arbitrary backend executable.
Polkit authorizes launching the helper; the helper and its supervisor enforce
the session lifetime.

Before enabling writes, the production client must check protocol compatibility
and required capabilities. An AppImage may be newer than an installed service
or the host CLI. A version mismatch needs an actionable setup message.

`GetCapabilities` now returns protocol version 1 and supported operations.
Installed mode advertises `interactive-control`, `persistent-services`, and
`next-boot-graphics` when configured. Portable mode advertises interactive
controls and rejects service changes and next-boot requests. Metadata can be
read before `Authorize`. An older service without this method needs an
incompatible-service message; it must not trigger portable elevation.

CLI discovery also needs a shared rule. The desktop currently searches `PATH`,
the generic service unit uses `/usr/bin/legion_cli`, and the NixOS module receives
a package path. The release implementation must resolve and validate one backend
for both reads and writes on each supported host.

## Trust and lifetime requirements

The download is code the user chooses to trust. The host's administrator policy
still decides whether that code can run with privileges. A password dialog alone
does not prove which executable, dependencies, or peer will be used.

The production design must establish:

- **Helper integrity:** the executable approved during authentication cannot be
  replaced before execution. Its interpreter, libraries, and loader paths belong
  to the same review. A checksum taken before a mutable-path launch is inadequate.
- **Backend integrity:** resolve the installed CLI and host tools through trusted
  paths. Retain executable validation and audit script dependencies, working
  directory, configuration loading, and environment. Do not inherit AppImage
  library search paths into privileged host commands.
- **Peer identity:** authenticate with D-Bus `EXTERNAL`, check kernel-reported
  credentials, and bind approval to one live app instance. A supplied PID or
  environment variable alone is not proof. Reject extra clients. Define the
  same-user threat boundary and handle PID reuse during authorization.
- **Server identity:** the app must verify it connected to its approved helper.
  The server authenticating the app proves only one direction of this connection.
- **Bounded lifetime:** startup, authentication cancellation, disconnect, crashes,
  idle sessions, and command timeouts have explicit cleanup paths. Stopping the
  direct CLI child is insufficient when it has descendants or inherited pipes.
- **Instance isolation:** simultaneous apps, stale sockets, updates, and retries
  cannot take over an existing authorization or replay a write. Installed and
  portable helpers need a shared rule for serializing hardware writes.

Stopping the helper ends access; it does not undo hardware settings already
applied. A timed-out or interrupted write needs a fresh read before retrying.

### Administrator startup experiment

The VM-only `portable_bootstrap_probe` tests systemd's existing
`org.freedesktop.systemd1.manage-units` Polkit action. Its launcher requests one
fixed helper through `StartTransientUnit`, with interactive authorization enabled.
The probe uses a synthetic CLI and refuses to run outside the marked disposable
VM. Production portable control still needs integration and review.

Before requesting approval, the launcher copies its own executable into a sealed
memory file and disables process dumping to prevent another ordinary process
from replacing its descriptor. The start request passes the sealed descriptor
to systemd as the helper's stdin. systemd sets up that descriptor before
executing `/proc/self/fd/0`, so delayed execution uses the manager's retained
snapshot. Replacing the downloaded file or recycling the launcher's PID cannot
change those bytes. AppImage FUSE launch still needs separate qualification.

A private Unix packet carries app and launcher pidfds captured before approval.
systemd retains this packet socket as the helper's stderr. The helper receives
owned process handles, rejects either process having exited, and redirects its
stderr before starting control. It never opens another process's executable
through a numeric PID. Tests reject queued handles after app or launcher death
and release a delayed start after killing the launcher.

The snapshot validator accepts x86-64 ELF executables. It requires a
root-controlled interpreter and library search directories, rejects relative
paths and `$ORIGIN`, and rejects path-bearing dependency names and ELF audit,
filter, or configuration objects. The privileged helper uses host libraries;
the desktop app may bundle its own. The host's loader, library cache, and
installed libraries remain part of the trusted host environment. Sealing fixes
the approved bytes; users still choose which download to trust.

The launcher connects to the fixed host system-bus socket. Its AppImage library,
module, and bus environment is not forwarded to the root helper. The systemd
authorization belongs to the launcher process. The host controls its policy and
authorization caching; production must keep the launcher limited to this fixed
request and explain the administrator session in the app.

The earlier direct `pkexec` snapshot idea is unsuitable: Polkit 127 resolves the
executable with `realpath()` before execution, turning a memory-file descriptor
path into a deleted-file name. Launching through a generic shell or dynamic
loader would add another privilege interface. The systemd experiment uses the
snapshot as the executable directly.

Run the guarded startup experiment with:

```bash
nix build .#checks.x86_64-linux.portable-bootstrap --print-build-logs
```

The VM supplies deterministic allow, deny, and authentication-required policies
for disposable test users. It tests startup from a user-owned path with spaces,
source replacement after sealing, root execution, environment isolation, missing
authentication agents, and launcher death during running and queued startup.
It also runs the ELF validation suite with normal root ownership. The probe
target is disabled by default and excluded from product installation.
The expanded startup VM passed on 2026-11-04 with systemd 262, GLib 2.88.3,
and Polkit 127.

The root session in `control/prototype/portable_control_helper.cc` shares the
production dispatcher and command runner. It authenticates one app with D-Bus
`EXTERNAL`, checks its kernel UID/PID, and observes both process handles received
from the startup packet. A recycled PID cannot inherit the session. Approval
trusts the app process and its code.

The VM app client verifies the root server before D-Bus authentication: the
underlying Unix socket must report UID 0 and the helper PID reported by the real
systemd unit. A user-owned impostor is rejected before authentication bytes are
sent. A different process, another user, and extra connections are rejected by
the helper. Portable `Authorize` establishes the API session after host approval.

The test covers synthetic enable/readback/restore, native argument validation,
fan-file cleanup, idle shutdown, helper crashes, and contention between helpers.
It uses a fixed CLI fixture compiled into the VM probe; callers cannot select a
root executable. The installed-service VM also verifies contention with a
portable session. These checks perform no hardware writes.

The production launcher's verified-endpoint handoff to Dart, host CLI discovery
and capability checks, live authentication-dialog cancellation, desktop prompts,
Debian qualification, and AppImage FUSE/extraction remain required before
enabling portable hardware writes.

### Backend process containment

Each validated backend operation runs in a systemd transient service. systemd
owns its control group and terminates descendants, including children that
detach with `setsid()` or double-fork. Startup, runtime, and stop deadlines are
enforced by systemd independently of the control helper. The helper also cancels
an acknowledged start that remains queued for five seconds.

The operation uses `BindsTo` and `After` to end when its helper service ends.
`JoinsNamespaceOf` shares the helper's private temporary directory so a backend
can read a temporary fan-curve payload. The operation retains the service's
filesystem, namespace, syscall, and privilege restrictions and trusted `PATH`.
When next-boot graphics requests are enabled, command units also retain the
private `legion-graphics-boot` state directory used by the installed helper.
The future portable administrator helper must itself run as a transient service.
These units are created at runtime and require no installed unit files.

The startup experiment creates a five-second transient timer before the helper
can start. Its cleanup service cancels a start still waiting on ordering
dependencies, even after launcher death. Once the helper receives live process
handles, it stops this startup timer and observes those handles directly.
Helper success or failure triggers the same cleanup service with replacement
job mode. The launcher observes the helper unit ending and exits, releasing its
unit reference. Cleanup also removes the private socket directory after
disconnect, idle exit, or a crash. Runtime limits bound a running helper.

Installed and portable helpers use `/run/legion-control/operation.lock` to
serialize writes. Each operation opens and locks the empty file independently.
systemd receives that descriptor as the backend's stdin, preserving EOF behavior
and retaining the lock while a backend or its descendants remain alive. Killing
a helper therefore cannot release the lock before systemd finishes cleanup.
Contending writes return `Busy`.

The root-owned shared runtime directory and empty lock file remain until reboot
to preserve one lock identity across helper exits and service restarts. Each
portable session's socket directory is removed separately. Ordinary portable use
installs no unit files or Polkit actions.

The runner pins the system manager's D-Bus owner and gives each operation a unique
unit name. It waits for terminal state, no pending job, and systemd's release of
the empty control group before releasing its unit reference. systemd can then
close its output descriptors and collect the unit. A failed unit with processes
still stuck in the kernel keeps the helper busy until the cleanup deadline.
Cancellation during startup waits for the start reply before requesting stop.
Uncertain cleanup disables further writes until the helper restarts.

Private-bus tests exercise the manager protocol and failure paths. The disposable
NixOS VM test exercises actual cgroup cleanup under the installed service's
sandbox with synthetic backends:

```bash
nix build .#checks.x86_64-linux.control-lifecycle --print-build-logs
```

The VM covers private payload visibility and removal, persistent next-boot
request/status/cancellation, graphics exit codes,
detached stdout holders, output limits, runtime deadlines, and client/helper
`SIGKILL`. Its fixture executables refuse to run outside the marked test VM.
The test passed on 2026-11-04 with the pinned NixOS environment: systemd 262,
GLib 2.88.3, and Polkit 127. Debian/Ubuntu versions still need qualification.
Live authentication-dialog cancellation still needs desktop qualification.

## Hardware-free prototype

Build the opt-in native probe and run the Dart client from the repository root:

```bash
cmake -S telemetry -B build/portable-control -G Ninja \
  -DBUILD_LEGION_CONTROL_SERVICE=ON \
  -DBUILD_PORTABLE_CONTROL_PROTOTYPE=ON
cmake --build build/portable-control --target portable_control_probe
dart run tool/probe_portable_control.dart \
  --helper build/portable-control/portable_control_probe
```

Use the development dependencies from [Contributing](../../CONTRIBUTING.md).
The probe runs as an ordinary user and uses a fixed synthetic backend. It
exercises the real private D-Bus transport and shared command validation with
simulated authorization. It does not contact the system bus, run `pkexec`, or
change hardware. Its target is disabled by default and is never installed.

The probe checks synthetic write/readback/restore, rejected writes before
authorization, native argument validation, fake authorization cancellation,
wrong-process and extra-client rejection, startup timeout/cancellation, and
cleanup after the client exits without closing its connection. It verifies that
the socket, fixture, and temporary directory are removed.

Passing the probe establishes transport and dispatch behavior. Real Polkit,
root-to-user peer authentication, executable integrity, whole-process-tree
cleanup, and real hardware readback require separate verification.

## Release verification

All three formats need versioned artifacts, desktop integration, checksums,
dependency notices, and matching source companions. Reuse
`tool/package_release.dart` for provenance, extending it to cover any additional
libraries and the helper included in release packages. Nix and distro-native
builds share source and release metadata; a Nix-linked binary is not a portable
Debian/AppImage build.

Packaging must supply a desktop entry, a redistributable hicolor icon, and
AppStream metadata. Choose and document the portable build's glibc baseline,
whether GTK is bundled, and which helper libraries come from the host. Include
their source and notices wherever libraries are redistributed.

The AppImage acceptance environment is a clean supported Debian-family desktop
with the driver, CLI, systemd, host libraries, and a Polkit authentication agent,
with our installed services absent.
Begin distribution qualification on Debian/Ubuntu and publish the exact tested
versions; extend that matrix as other distributions are checked. Verify:

- FUSE launch and extract-and-run, including paths containing spaces.
- Administrator approval, denial, cancellation, and a missing Polkit agent.
- Hardware change, independent readback, and restoration on a recorded device.
- UI/launcher/helper crashes, backend descendants, and bounded cleanup.
- Multiple app instances, installed-service coexistence, and version mismatch.
- No persistent service, bus policy, Polkit action, or permission change from
  ordinary portable use.

CI can prove builds and hardware-free behavior. Record desktop authorization and
hardware checks separately, with the distribution and component versions.

## References

Context7 was unavailable during this investigation. The API research used primary
documentation and the resolved local dependency sources:

- [Polkit pkexec](https://polkit.pages.freedesktop.org/polkit/pkexec.1.html)
- [GLib D-Bus server](https://docs.gtk.org/gio/class.DBusServer.html)
- [GLib peer credentials](https://docs.gtk.org/gio/method.DBusConnection.get_peer_credentials.html)
- [Dart dbus client](https://pub.dev/documentation/dbus/latest/dbus/DBusClient-class.html)
- [AppImage FUSE and extraction](https://docs.appimage.org/user-guide/troubleshooting/fuse.html)
- [Linux memfd and seals](https://man7.org/linux/man-pages/man2/memfd_create.2.html)
- [systemd transient units](https://www.freedesktop.org/software/systemd/man/latest/systemd-run.html)
- [systemd manager D-Bus API](https://www.freedesktop.org/software/systemd/man/latest/org.freedesktop.systemd1.html)
- [systemd process termination](https://www.freedesktop.org/software/systemd/man/latest/systemd.kill.html)
