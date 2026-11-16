# Official Flutter template shutdown diagnostic

This branch is a temporary diagnostic, not a deployment change. It uses the
existing Ubuntu VM transfer/collection workflow with an untouched Linux counter
template instead of the application package. Do not merge it.

## Build

The retained official Flutter 3.50 SDK archive is mounted read-only into the
existing Ubuntu 22.04 packaging builder. `build.sh` checks the archive checksum,
then runs `flutter create --platforms=linux --project-name=shutdown_template`
and `flutter build linux --release`. The SDK is extracted inside the disposable
container; no shared SDK is changed. `flutter analyze` and the generated counter
test passed. Source hashes before/after building match. The template has no
added plugin, retained engine reference, or application changes.

Builder image ID:
`sha256:9b05b894a49b0b205abdfc827ca0ec6ec5672769e2a60182a8747f7623203a34`.
`diagnostic-assets/template` contains its source, bundle, SDK identity, and
checksums, including engine and AOT bytes. It does not contain the SDK archive.

## Bounded hosted diagnostic

The draft PR targets `fix/stable-deployment`, so only its diagnostic workflow
and repository-wide scanning run, not the main application build matrix. The
diagnostic requires the standard `ubuntu-latest` host with KVM. CPU identity is
recorded, not restricted by vendor.

The Ubuntu 22.04 guest installs the distro GTK/LLVM/Mesa stack, systemd-coredump,
GDB, DBus/AT-SPI, Xvfb, and Openbox. Openbox supplies the untouched template's
ordinary window decoration and visible X; the original app had its own close
button. It is not a compositor or an application launcher. Guest package
versions and the downloaded image checksum are retained; this is not a claim
that every package version matches the original failure.

A controlled approved-user abort must produce a core and all-thread GDB trace
before the template launches. Each attempt launches the ordinary release
executable, asserts visible initial counter text and zero, verifies loaded
LLVM15/swrast, then requests a normal window-manager close with `wmctrl -ic`.
An independent X RECORD observer must see Openbox deliver `WM_DELETE_WINDOW`
to that client before its exit is judged. Twenty exit-zero closes are required;
the first failure stops the sequence. GLib/GObject/Pango criticals remain
failures. The application under test is never signalled or forcibly destroyed.
On a post-delivery hang, the root guest fixture captures its live all-thread
GDB stack before the disposable VM is discarded.

The existing VM transfer path collects failure cores, all-thread traces, maps,
build IDs, matching guest libraries, screenshots, versions, and logs into an
Actions diagnostic artifact retained for seven days. No raw core is attached
to an upstream comment. A template crash must be classified before comparing
it with the app's raster-versus-exit evidence; a task-runner UAF is a different
result. Twenty passes establish non-reproduction here, not a fix for the app.

## Corrected close/session preflight

Run 43919030365 remains inconclusive. A disposable GTK-only preflight exposed
the targeting defect: `xdotool getwindowgeometry` reported X=2,Y=40 while
`xwininfo` reported the same client's actual root origin X=1,Y=20. With a
20-pixel top frame, the old formula clicked Y=30 inside the client instead of
the visible titlebar at Y=0–19. Its saved client-only screenshot could not show
that mistake. The corrected probe retains the root screenshot, full window
tree, both geometry reports, properties, PIDs, and before/after state.

The new session uses an empty inherited environment with the approved user's
HOME and a UID-owned mode-0700 XDG_RUNTIME_DIR, then private `dbus-run-session`
and real AT-SPI. The local ordinary GTK fixture passed its delete-event
callback and independent server-delivery check with exit zero and no criticals.
The hosted guest repeats that preflight before launching Flutter. Template
source, bundle, SDK/runtime and AOT hashes remain unchanged.

`wmctrl -ic` sends the standard EWMH `_NET_CLOSE_WINDOW` request to the window
manager, not XDestroyWindow. The probe first requires the client to advertise
`WM_DELETE_WINDOW`. In Openbox 3.6.1, `openbox/event.c:1439` handles this request
through `client_close`, exactly as the Close action in
`openbox/actions/close.c:16` does. `client_close` sends `WM_DELETE_WINDOW` when
the client supports it. The observer records that actual delivery; the GTK
fixture also confirms its delete-event callback. This uses the same normal
client protocol as the titlebar X, but it is not a literal pointer click, and
that distinction remains part of the result.

Protocol: https://specifications.freedesktop.org/wm-spec/latest/ar01s04.html
Source: https://archive.ubuntu.com/ubuntu/pool/universe/o/openbox/openbox_3.6.1.orig.tar.gz
