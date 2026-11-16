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

## One hosted run

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
LLVM15/swrast, then clicks the window's visible X. Twenty exit-zero closes are
required; the first failure stops the sequence. GLib/GObject/Pango criticals
remain failures. Forced termination only cleans up a failed probe; it is never
counted as a successful normal close.

The existing VM transfer path collects failure cores, all-thread traces, maps,
build IDs, matching guest libraries, screenshots, versions, and logs into an
Actions diagnostic artifact retained for seven days. No raw core is attached
to an upstream comment. A template crash must be classified before comparing
it with the app's raster-versus-exit evidence; a task-runner UAF is a different
result. Twenty passes establish non-reproduction here, not a fix for the app.
