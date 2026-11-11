# AppImage qualification build

Build the desktop app and temporary helper together on Ubuntu 22.04. The AppImage
contains the Flutter bundle and uses host GTK, GLib, Polkit, EGL/GLES graphics,
and C/C++ libraries.
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
Source packaging requires a clean committed checkout. NixOS users can use the
[Nix frontend](nix.md); this artifact targets the Ubuntu host library baseline.

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
The source companion contains runtime source archives and their license files;
the SDK archive is identified by URL and hash and obtained separately.

The AppDir reuses the project icon and app identifier. It contains desktop and
AppStream metadata, Flutter notices, project and font/native licenses, and runtime
licenses. Installed service units, D-Bus policies, and Polkit actions are removed
from the AppDir. Running it installs no persistent integration files.

The AppRun script sets the desktop library path. Host CLI reads and the ordinary
helper launcher use the existing environment filter to remove bundled loader and
module settings. The privileged helper uses host loader paths. Packaging rejects
Nix store references in ELF loader metadata and any helper RPATH/RUNPATH.

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
Paths contain spaces. The acceptance guest has no JVM or installed Legion service.
Test-only Polkit decisions approve the synthetic helper session. Live password
prompts remain a separate check. Persistent service, policy, and udev files must
match their state before the AppImage tests.

For a desktop trial, verify `SHA256SUMS`, make the AppImage executable, and open
it as your normal user. With FUSE unavailable, extract it with
`--appimage-extract` and run `squashfs-root/AppRun`.

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
