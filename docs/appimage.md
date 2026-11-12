# AppImage qualification build

For NixOS, use the [native Nix package](nix.md) or launch this AppImage through
the pinned Nix launcher from the project directory in a regular host terminal:

```bash
nix run .#appimage-run -- /path/to/legion-frontend.AppImage
```

The launcher uses Nix to cache an extracted copy, changes only the desktop and
image-loader executables' interpreter paths, and supplies core and graphics
libraries from the pinned Nixpkgs. It preserves every bundled library and the
static helper. It leaves the host ownership and process namespaces intact, so
CLI trust checks see real root ownership. The stock FHS `appimage-run` hides that
ownership and is unsuitable for these checks. Direct AppImage launch on an
unconfigured NixOS host remains unqualified.

Build the desktop app and temporary helper together on Ubuntu 22.04. The AppImage
contains Flutter, GTK, GLib, Pango, font rendering libraries, image loaders,
settings schemas, icons, and DejaVu fonts. It bundles `xdg-user-dir` to find the
Documents directory used by the app's existing Hive storage.

The desktop still uses the host's glibc 2.35 or newer, C/C++ runtime, X11 or
Wayland client libraries, and EGL/GLES graphics stack. These are the loader and
driver interfaces; bundling older copies can prevent newer GPU drivers from
loading. The native-runtime manifest lists the exact host library names found
during packaging. GTK and its remaining dependencies are private to the app.

The temporary helper is a static ELF executable. It embeds a separate cleanup
ELF below 64 KiB; newer systemd managers cannot serialize the full static helper
as retained standard-input data. Both images use validated sealed snapshots.
Startup, authorized root control, and cleanup need no ELF interpreter or shared
libraries. The authorization request carries both sealed images. Root execution
loads no libraries from the AppDir.
Systemd and the host Polkit service still authorize startup.

Temporary hardware access requires the installed driver and `legion_cli`, systemd,
and a desktop authentication agent. Installed service remains the default mode;
choose Temporary helper in Settings and reopen the app to use it.

This is a qualification build. Desktop password dialogs, actual CLI package
dependencies, hardware readback, and other distributions need separate testing.

On 2026-11-11, the Ubuntu 22.04.5 VM checks passed for FUSE launch, extracted
launch, and synthetic helper write/readback/restore from both locations. The
desktop rendered its first Flutter frame with GTK 3.24.33, FUSE 3.10.5, and Mesa
23.2.1. The guest had no Legion driver, JVM, or installed Legion service. The
existing NixOS bootstrap check also passed with the shared test driver.

## Build

The builder needs Docker, Git, Python 3, and curl. It runs the compiler as an
ordinary user in an Ubuntu container. It mounts no host devices or system bus.
Source packaging requires a clean committed checkout.

```bash
curl -fL https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.9-stable.tar.xz -o /tmp/flutter-3.47.9.tar.xz
python3 tool/fetch_appimage_runtime.py build/appimage-inputs
bash tool/build_appimage.sh /tmp/flutter-3.47.9.tar.xz build/appimage-inputs build/appimage-release
```

The scripts check the SDK, runtime, and source archive hashes against
`packaging/appimage/build-inputs.json`. The output includes the versioned
`.AppImage`, source companion, build manifest, and `SHA256SUMS`. Keep these files
together. The source manifest records every shipped app/helper file and portable
build flags. A helper or native-library change invalidates its source pairing.
The source companion contains the AppImage runtime sources and the exact Ubuntu
source packages for every copied desktop library, runtime data package, and
static helper archive. `release-inputs/native/native-runtime.json` records binary
and source package versions and archive hashes. Each `.dsc` and its companion
archives retain the distro patches and build recipes. Copyright notices and
license texts ship in the app. `REBUILD.md` explains modifying and relinking the
helper. The SDK archive is identified by URL and hash and obtained separately.

The AppDir reuses the project icon and app identifier. It contains desktop and
AppStream metadata, Flutter notices, project and font/native licenses, and runtime
licenses. Installed service units, D-Bus policies, and Polkit actions are removed
from the AppDir. Running it installs no persistent integration files.

AppRun selects the bundled desktop libraries, schemas, fonts, and GIO modules.
It creates an image-loader cache for the current mount path and removes that
cache when the desktop exits. Signals stop its desktop child and clean up the
cache. Host CLI reads and helper startup filter out the bundled library, font,
module, schema, and data paths. Packaging rejects Nix store loader references and
any dynamic interpreter, shared dependency, RPATH, or RUNPATH in the static helper.

## Test the artifact

Use the [Ubuntu VM runner](architecture/portable-distro-qualification.md) with the
additional release directory:

```bash
bash tool/test_portable_distro.sh /tmp/jammy.img "$checksum" \
  build/appimage-qualification --appimage build/appimage-release
```

The VM first runs the native helper checks. It then verifies artifact hashes,
opens a real Flutter window under Xvfb through FUSE and through extraction, and
uses the bundled helper from both locations for synthetic write/readback/restore.
Paths contain spaces. The acceptance guest has no GTK, JVM, or installed Legion
service. Both normal launches must render their first frame and map GTK, GLib,
and Pango from the AppImage. The helper must load no shared libraries. The tests
also verify the bundled directory command and retain the desktop memory maps.
Test-only Polkit decisions approve the synthetic helper session. Live password
prompts remain a separate check. Persistent service, policy, and udev files must
match their state before the AppImage tests.

Test the same artifact through the NixOS launcher:

```bash
bash tool/test_appimage_nixos.sh build/appimage-release/*.AppImage build/appimage-nixos-qualification
```

This separate NixOS VM checks the public launch command, first frame, bundled
GTK libraries, unchanged host namespace, and static helper write/readback/restore
and cleanup. It uses a
synthetic CLI in the system profile. CI runs both VM checks and keeps their
evidence. Tag-release preparation requires both checks for this bundled format
and verifies that they tested the same AppImage hash and source commit.

## Desktop trial

On a host with the core library and graphics baseline, verify `SHA256SUMS`, make the AppImage
executable, and open it as your normal user from a regular desktop terminal.
The FUSE path needs access to `/dev/fuse`. The pinned runtime also looks for a
root-owned setuid `fusermount` or `fusermount3` executable in `PATH`. Ubuntu's
`fuse3` package supplies the mounting tool.

`No suitable fusermount binary found` can mean the tool is missing, its ownership
or permissions do not meet the runtime's checks, or it cannot execute. A terminal
inside an FHS sandbox can hide root ownership and prevent setuid mounting. In
that case, retry from a regular desktop terminal before assessing the host's
FUSE setup. An explicit `FUSERMOUNT_PROG` path cannot remove a mount restriction.

An error loading `libgtk-3.so.0` after a `/tmp/.mount_...` path means mounting
succeeded and the desktop app could not load GTK. Earlier qualification builds
used host GTK. The bundled build includes it; verify that you are testing the
new artifact and its matching checksums. On NixOS, use the compatibility runner
above so the core loader and graphics libraries are also available without
changing the CLI ownership view.

To test the separate extraction path on a compatible host, run
`--appimage-extract` and then `squashfs-root/AppRun`. Record this result separately
from FUSE launch.

## Runtime inputs

The versioned type-2 runtime `20251108` is pinned by hash. Its build source,
libfuse 3.15.0, squashfuse 0.5.2, and source/notice snapshots for its Alpine 3.21
libraries accompany the app source. The runtime build recipe and libfuse patch
remain in the upstream source archive. Upstream provides no complete manifest
of the binary's Alpine package revisions; those revisions remain unverified.

The type-2 image is assembled from that runtime and a SquashFS payload using
Ubuntu's `mksquashfs`. See the [AppImage format](https://docs.appimage.org/reference/architecture.html),
[AppDir specification](https://docs.appimage.org/reference/appdir.html), and
[runtime build sources](https://github.com/AppImage/type2-runtime/tree/20251108).
