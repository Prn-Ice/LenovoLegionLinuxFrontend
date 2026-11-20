# Hardware control and release formats

## Decision

Nix, Debian packages, and AppImage are first-class targets for the first release.
The AppImage goal is: install the supported driver and CLI, download the app,
open it, and authorize interactive hardware changes without installing our
system service.

The VM experiment connects approved administrator startup to the real typed
control API with a synthetic CLI. The desktop checks protocol compatibility
before API authorization. Backend process containment, shared write locking,
Dart launcher supervision, and trusted executable validation are implemented.
The bundled helper discovers the installed CLI and checks its command syntax
before accepting a connection. Host CLI package qualification and release
publication remain open. See the
[public backlog](../../BACKLOG.md).

The privileged control helper is a bundled process that performs approved
hardware operations as root. The interface calls this **administrator access**.
It is the app's only hardware-control connection and ends when the app closes
or the session expires.

## Installation experience

The intended release experience is:

| Format | Desktop app | Hardware control |
| --- | --- | --- |
| NixOS | Nix package | Bundled session helper |
| Debian | Desktop package | Bundled session helper |
| AppImage | Download and run | Bundled helper runs for the authorized app session |

Nix on another distribution can supply the desktop package. Driver setup and
helper integration need testing on that host.

The AppImage runs the UI as the current user. Readable sysfs data stays
unprivileged. When a write needs authorization, the flow is:

1. Explain that administrator access lasts for this app session.
2. Ask the host's Polkit agent to authorize the fixed control helper.
3. Connect this app instance to that helper over a private D-Bus connection.
4. Send the existing typed `LegionControl1` operations.
5. End the helper and its backend processes when the connection ends.

A denied request, incompatible helper, or failed backend command must not
trigger a second privilege mechanism automatically.

Boot-time graphics reconciliation requires persistent system integration.
For CPU watts, the app asks permission to start a read-only helper session.
The helper samples the kernel energy counter once per second. Direct keyboard
HID access requires separate host setup.

## Shared control implementation

The native helper validates each typed request in `control/control_dispatch.cc`. Host Polkit approval starts the helper. Its private socket accepts only the app process that requested approval.

After transport preparation, `LegionControlClient` checks protocol compatibility
and required capabilities before API authorization. Session setup includes
host approval to start the helper. The client shares the initial metadata
request between concurrent callers and caches a successful result for that
connection. Unknown capabilities are ignored.
If systemd rejects startup approval before acknowledging the start, the launcher
exits without a helper. After its cleanup finishes, a later explicit action can
request fresh approval in the same app. Concurrent requests share one attempt;
denial never retries automatically. Timeouts, uncertain cleanup, CLI mismatch,
and failures after a start acknowledgement still require a new app session.
An older service, malformed reply, incompatible protocol, or missing interactive
controls produces setup guidance before API authorization or writes.

`GetCapabilities` returns protocol version 1 and the `interactive-control` capability.

Compatibility checks and service lookup have five-second deadlines. Transport
preparation and API authorization have separate deadlines; the backend command
deadline starts after approval completes. Closing the client rejects pending
requests immediately, including a pending metadata reply or authorization.
If opening the bus connection finishes after disposal,
the transport closes it again. A write-queue timeout also closes control access
and prevents retries in that session. A late authorization reply cannot dispatch
the timed-out write. Read current settings and restart the app before retrying.

The native shared validator in `control/trusted_executable.cc` checks root
ownership of every selector, directory, symlink, and executable. It rejects
unsafe write permissions and resolves links through pinned directory descriptors.
The fixed host CLI search checks the system NixOS profile, the system Nix profile,
`/usr/bin`, and `/usr/local/bin`. A present unsafe selector stops discovery.
Both helper builds use the validator. The
production helper uses fixed discovery; the VM probe has a fixed synthetic CLI.

Before exporting its private endpoint, the helper runs `legion_cli --help` in a
systemd-managed backend unit with a three-second runtime limit and bounded
output. It requires the exact interactive command names from the shared command
contract and the `--donotexpecthwmon` flag. App or launcher death cancels this
check and waits for cleanup. This read-only startup check uses a separate runner,
so it can finish while another session holds the hardware write lock.

The check establishes advertised command syntax and successful CLI startup in the
backend environment. CLI package versions, scripts, imports, configuration files,
and hardware behavior still need distribution qualification.

App reads use native `findHostCli` before any authorization. This accepts no
caller-selected path and resolves fixed locations on a GLib worker. Discovery
for unprivileged reads establishes no root trust: an AppImage compatibility
namespace may hide host file ownership. The root helper independently applies
the full ownership validator on the host before executing privileged commands.
`LegionCliService` shares and caches the canonical read path across readers.
The root helper reports its selected CLI in percent-encoded readiness output.
The helper transport compares both paths before creating the private peer; a
changed selection ends startup and requires a fresh app session. Discovery during
disposal cannot start a late read command or helper. Host CLI reads use the same
loader/module environment filter as the ordinary-user launcher.

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
  app helpers need a shared rule for serializing hardware writes.

Stopping the helper ends access; it does not undo hardware settings already
applied. A timed-out or interrupted write needs a fresh read before retrying.

### Administrator startup experiment

The VM-only `helper_bootstrap_probe` and bundled production helper share
`control/helper_bootstrap.cc`. The VM tests systemd's existing
`org.freedesktop.systemd1.manage-units` Polkit action. Its launcher requests one
fixed helper through `StartTransientUnit`, with interactive authorization enabled.
The probe uses a synthetic CLI and refuses to run outside the marked disposable
VM. The production build accepts only its session, sealed helper, and cleanup
entry points; the VM-only replacement and queued-start controls are excluded.

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
root-controlled interpreter and library search directories, using the same
descriptor-based walk as CLI validation. It rejects relative
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
nix build .#checks.x86_64-linux.helper-bootstrap --print-build-logs
```

The VM supplies deterministic allow, deny, and authentication-required policies
for disposable test users. It tests startup from a user-owned path with spaces,
source replacement after sealing, root execution, environment isolation, missing
authentication agents, and launcher death during running and queued startup.
It also runs the ELF validation suite with normal root ownership. The probe
target is disabled by default and excluded from product installation.
The expanded startup VM passed on 2026-11-11 with systemd 262, GLib 2.88.3,
and Polkit 127.

The production build also passes synthetic write/readback/restore, denied
authorization, missing-agent, incompatible CLI, CLI failure, excessive output,
and hung-help checks in this VM. The CLI fixture verifies its actual working
directory and environment. Root snapshot tests reject an administrator-owned
alias whose target crosses a user-owned directory.

The root session in `control/control_session.cc` shares the
production dispatcher and command runner. It authenticates one app with D-Bus
`EXTERNAL`, checks its kernel UID/PID, and observes both process handles received
from the startup packet. A recycled PID cannot inherit the session. Approval
trusts the app process and its code.

The VM app client verifies the root server before D-Bus authentication. The
helper reports its unique host system-bus connection name. The host bus must
report UID 0 and the same PID as the real systemd unit and underlying socket.
A process descriptor pins that PID during setup. A user-owned impostor is
rejected before authentication bytes are sent. A different process, another
user, and extra connections are rejected by
the helper. `Authorize` establishes the API session after host approval.

The test covers synthetic enable/readback/restore, native argument validation,
fan-file cleanup, idle shutdown, helper crashes, and contention between helpers.
It uses a fixed CLI fixture compiled into the VM probe; callers cannot select a
root executable. These checks perform no hardware writes.

The desktop's private connection is implemented through the native Linux host.
`NativeControlConnection` accepts an endpoint from an approved launch and
uses the `io.github.prnice.legion/control` Flutter method channel.
`linux/runner/control_channel.cc` owns the GDBus connection in the same
process as the app. This preserves the helper's app-PID authentication.

The shared verifier in `control/control_peer.cc` checks systemd's helper PID,
the host bus's UID/PID, and the raw Unix socket's PID before authentication.
The [D-Bus credentials API](https://dbus.freedesktop.org/doc/dbus-specification.html#bus-messages-get-connection-credentials)
provides the host identity even when a namespace maps socket UID 0 to `nobody`.
It pins the systemd manager's unique bus owner during lookup. Connection setup
runs on a GLib worker with a five-second deadline and explicit cancellation.
Each native session has its own identifier; a late callback or close from an
older session cannot replace or close a newer connection. Destroying the Flutter
view cancels startup and closes its peer. The VM client uses this same verifier,
including asynchronous connections, stalled authentication, and cancellation.

The helper and native channel share `control/control_protocol.h`.
The channel checks method names, argument types, and payload limits against that
contract. The existing `LegionControlClient` checks protocol capabilities and
retains the same typed operations and error translation.

`ControlLauncher` starts the fixed bundled executable with `--control`,
a sanitized host environment, and a fixed working directory. It checks the
launcher PID, unit name, helper PID, and socket path in bounded readiness output.
`HelperControlTransport` owns that launcher and its native private peer.
Closing during startup prevents a late connection; a child that starts after
disposal is stopped. Shutdown escalates from SIGTERM to SIGKILL, and launcher
exit closes the peer. Unit tests cover these races and a real unprivileged child
that ignores SIGTERM.

The provider creates the app's connection to the privileged control helper.
The launcher accepts production `legion-control-helper-UUID.service` sessions and the guarded
VM probe names. CLI setup failures stop startup before peer creation and reach
Dart as typed setup errors. The production helper has a 15-minute idle limit and
a 12-hour session limit. The launcher observes the running helper after approval;
its initial authorization deadline no longer ends an active session.

Build the helper separately for native qualification with:

```bash
cmake -S control -B build/control-helper -G Ninja \
  -DBUILD_CONTROL_HELPER=ON
cmake --build build/control-helper --target legion_control_helper
```

The target produces `legion-control-helper`. Standard Linux builds bundle it at
the desktop launcher's expected `libexec/legion-control-helper` path:

```bash
flutter build linux --release
```

The helper uses host libraries rather than the app bundle's `$ORIGIN` search
path. Nix builds set canonical store library directories and use `patchelf` after
installation to remove compiler-injected development paths. Other builds use the
host loader cache. This target requires CMake 3.16; Nix qualification bundles also
require `patchelf`. The Nix development build retains store dependencies and
still needs a separate portable distribution build.

Settings shows helper availability without an authorization selector. Opening
Settings requires no administrator approval. Choosing **Allow** at startup
starts a CPU power session. The first hardware change starts its own control
session. A missing helper produces setup guidance. A denied
startup can be retried explicitly after cleanup in the same app; uncertain
cleanup requires reopening it.

Helper setup failures have typed recovery guidance. Distribution checks and
desktop trials are recorded in the [AppImage](../appimage.md),
[Debian](../debian.md), and [Nix](../nix.md) instructions. Synthetic VM checks
do not establish real hardware behavior.

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
Command units use `/` as their working directory, a host command search path,
C locale, an empty home path, and Python isolation flags. The downloaded app
environment is not forwarded.
These units are created at runtime and require no installed unit files.

The launcher creates a five-second transient timer before the helper
can start. Its cleanup service cancels a start still waiting on ordering
dependencies, even after launcher death. Once the helper receives live process
handles, it stops this startup timer and observes those handles directly.
Helper success or failure triggers the same cleanup service with replacement
job mode. Cleanup executes the same approved sealed bytes with `--cleanup`.
The unit retains these bytes as `StandardInputData` because older systemd
versions release inactive units' file descriptors. At cleanup, those versions
create a sealed input from the retained bytes; newer versions can use the
original descriptor. Cleanup reports completion after verifying the executable
is still sealed. The launcher observes the helper unit ending and exits,
releasing its unit reference. Cleanup also removes the private socket directory after
disconnect, idle exit, or a crash. Runtime limits bound a running helper.

App sessions use `/run/legion-control/operation.lock` to
serialize writes. Each operation opens and locks the empty file independently.
systemd receives that descriptor as the backend's stdin, preserving EOF behavior
and retaining the lock while a backend or its descendants remain alive. Killing
a helper therefore cannot release the lock before systemd finishes cleanup.
Contending writes return `Busy`.

The root-owned shared runtime directory and empty lock file remain until reboot
to preserve one lock identity across helper exits and service restarts. Each
app session's socket directory is removed separately. App use
installs no unit files or Polkit actions.

The runner pins the system manager's D-Bus owner and gives each operation a unique
unit name. It waits for terminal state, no pending job, and systemd's release of
the empty control group before releasing its unit reference. systemd can then
close its output descriptors and collect the unit. A failed unit with processes
still stuck in the kernel keeps the helper busy until the cleanup deadline.
Cancellation during startup waits for the start reply before requesting stop.
Uncertain cleanup disables further writes until the helper restarts.

Private-bus tests exercise the manager protocol and failure paths. The NixOS and Ubuntu VMs exercise process cleanup and authorization with synthetic hardware. See the [helper tests](control-helper-tests.md).

## Hardware-free prototype

Build the opt-in native probe and run the Dart client from the repository root:

```bash
cmake -S control -B build/control-helper -G Ninja \
  -DBUILD_CONTROL_PROTOTYPE=ON
cmake --build build/control-helper --target control_probe
dart run tool/probe_control.dart \
  --helper build/control-helper/control_probe
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
AppStream metadata. Choose and document the AppImage build's glibc baseline,
whether GTK is bundled, and which helper libraries come from the host. Include
their source and notices wherever libraries are redistributed.

The AppImage acceptance environment is a clean supported Debian-family desktop
with the driver, CLI, systemd, host libraries, and a Polkit authentication agent,
on a clean host.
Begin distribution qualification on Debian/Ubuntu and publish the exact tested
versions; extend that matrix as other distributions are checked. Verify:

- FUSE launch and extract-and-run, including paths containing spaces.
- Administrator approval, denial, cancellation, and a missing Polkit agent.
- Hardware change, independent readback, and restoration on a recorded device.
- UI/launcher/helper crashes, backend descendants, and bounded cleanup.
- Multiple app instances,  version mismatch.
- No persistent service, bus policy, Polkit action, or permission change from
  app use.

CI can prove builds and hardware-free behavior. Record desktop authorization and
hardware checks separately, with the distribution and component versions.

The [Ubuntu helper tests](control-helper-tests.md) build and
tests the production helper against distro libraries in a disposable VM. Its
synthetic CLI checks startup and containment before release packaging.

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
