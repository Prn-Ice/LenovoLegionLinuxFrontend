# AppImage qualification build

On NixOS, use the standard [AppImage support](https://wiki.nixos.org/wiki/Appimage).
Set these options in your NixOS configuration and apply the configuration:

```nix
programs.appimage = {
  enable = true;
  binfmt = true;
};
```

Launch with the standard runner:

```bash
appimage-run ./legion-frontend.AppImage
```

With `binfmt` enabled, executable AppImages also launch directly. The runner
extracts and caches the AppImage in its usual compatibility environment. The
app resolves fixed host CLI locations for unprivileged reads. The host root
helper independently validates the CLI before privileged execution, and the
app requires both paths to match. The host system bus reports the helper's
actual UID and PID, and the client checks both against systemd, a pinned process
handle, and the socket's PID before authentication. It never accepts
namespace-visible `nobody` ownership as root evidence. This uses no project launcher or patched
executables. The [native Nix package](nix.md) is also available.

For a container-free local image built from this repository's flake, see
[the Nix guide](nix.md#local-appimage). That image is for testing and does not
replace this release flow.

Build the desktop app and privileged control helper together on Ubuntu 22.04.
The AppImage contains Flutter, GTK, GLib, Pango, font rendering libraries, image loaders,
settings schemas, icons, and DejaVu fonts. It bundles `xdg-user-dir` to find the
Documents directory used by the app's existing Hive storage.

The desktop still uses the host's glibc 2.35 or newer, C/C++ runtime, X11 or
Wayland client libraries, and EGL/GLES graphics stack. These are the loader and
driver interfaces; bundling older copies can prevent newer GPU drivers from
loading. The native-runtime manifest lists the exact host library names found
during packaging. GTK and its remaining dependencies are private to the app.

The privileged control helper is a static ELF executable. It embeds a separate
cleanup ELF below 64 KiB; newer systemd managers cannot serialize the full static helper
as retained standard-input data. Both images use validated sealed snapshots.
Startup, authorized root control, and cleanup need no ELF interpreter or shared
libraries. The authorization request carries both sealed images. Root execution
loads no libraries from the AppDir.
Systemd and the host Polkit service still authorize startup.

Hardware access requires the installed driver and administrator-controlled
`legion_cli`, systemd, Polkit, and a desktop authentication agent. The app uses
the bundled privileged control helper from its first launch. The first privileged
action requests approval; closing the app ends the helper session.

### Integrated graphics only

On supported laptops, open **GPU** and choose **Set up iGPU-only at
startup**. Approve the admin prompt, choose **Integrated graphics only**, then
restart. This requires a host `legion_cli` with `graphics-mode boot-support`,
system-wide `lsof`, and working NVIDIA runtime power management. The startup
command uses the installed CLI, so moving or replacing the AppImage keeps boot
support available. [Driver CLI with boot support](https://github.com/Prn-Ice/LenovoLegionLinux/commit/3492884b83c4fb626cba4e4ddc32b3ef3dcc5f70)

Choose **Remove boot support** on the same page to undo the AppImage setup. If
you deleted the AppImage, run:

```bash
sudo legion_cli graphics-mode boot-support disable
```

Removing the last source of boot support cancels a pending switch. To return
to Hybrid after iGPU-only has taken effect, choose Hybrid in the app or run
`sudo legion_cli graphics-mode set hybrid`.

This is a qualification build. Desktop password dialogs, actual CLI package
dependencies, hardware readback, and other distributions need separate testing.

Build `46b827e`, using official Flutter 3.47.9, passed Ubuntu 22.04 FUSE and
extracted launches, normal window closes, and synthetic helper
write/readback/restore. The same AppImage passed
official NixOS `appimage-run` control checks and ten normal Wayland closes.
Neither VM reported Pango font errors. The user also confirmed the font fix on
KDE Wayland with hybrid graphics. These checks do not establish real hardware
control or desktop password-prompt behavior.

Current official Flutter 3.50.0 packages pass automated acceptance for all three
formats; see [the release record](releases.md#deployment-status-17-november-2026)
for the exact commit, CI run, and artifact identities. The user also confirmed
that the corrected AppImage works on their desktop, and previously confirmed
authorization retry. Physical readback, restoration, helper cleanup, and numeric
exit status still need an explicit record for the final candidate.

Wayland startup still reports `Unable to load  from the cursor theme`.
Flutter 3.50 initializes its cursor name to an empty string before GTK realizes
the view. Track the upstream fix in
`lllf-dt0.5.10.1`. Keep the standard launch command; the package includes no
cursor shim or log filter.

## Build

The builder needs Docker, Git, jq, and curl. It runs the compiler as an
ordinary user in an Ubuntu container. It mounts no host devices or system bus.
Source packaging requires a clean committed checkout.

```bash
curl -fL https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.50.0-stable.tar.xz -o /tmp/flutter-3.50.0.tar.xz
bash tool/fetch_appimage_runtime.sh build/appimage-inputs
bash tool/build_appimage.sh /tmp/flutter-3.50.0.tar.xz build/appimage-inputs build/appimage-release
```

If a cached builder's exact source package returns HTTP 404, refresh the Ubuntu
builder, then rerun the build. This updates its installed packages and source
indices together:

```sh
docker build --no-cache --tag lllf-appimage-builder:ubuntu22.04 \
  --file packaging/appimage/Dockerfile packaging/appimage
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
helper. The manifest identifies the SDK archive by URL and hash; download it
separately.

The AppDir reuses the project icon and app identifier. It contains desktop and
AppStream metadata, Flutter notices, project and font/native licenses, and runtime
licenses. Packaging removes installed service units, D-Bus policies, and Polkit
actions from the AppDir. Running it installs no persistent integration files.

AppRun selects the bundled desktop libraries, schemas, fonts, and GIO modules.
It starts in the AppDir so bundled Fontconfig 2.13 can resolve `usr/share/fonts`.
That version does not support the newer `prefix="relative"` configuration syntax.
It creates an image-loader cache for the current mount path and removes that
cache when the desktop exits. Signals stop its desktop child and clean up the
cache. Host CLI reads and helper startup filter out the bundled library, font,
module, schema, and data paths. Packaging rejects Nix store loader references and
any dynamic interpreter, shared dependency, RPATH, or RUNPATH in the static helper.

## AppImage icons

Dolphin's file preview and Plasma's running-app icon use different lookups.
The AppImage includes a PNG `.DirIcon` for file previews. KDE's installed
AppImage thumbnail plugin successfully decoded the original official 3.50
image and the user's Inkscape comparison image. That plugin did not reproduce
the reported missing Dolphin preview; the running-app fix below does
not establish a fix for the file-manager display.

Use the standard launch command above. Plasma can read an AppImage's bundled
desktop entry and icon through the running process's `APPDIR`; users should not
need to copy desktop files or install another launcher to get the taskbar icon.

The AppDir root uses `Icon=legion_frontend` with matching PNG/SVG files and
`.DirIcon`. Plasma 6.8's AppImage fallback mistakes the last part of a dotted
icon name for a file extension. A short root icon name avoids that lookup error.
The desktop filename, native application ID, and installed-package icon name
remain `io.github.prnice.legion_linux_frontend`. The Legion artwork is unchanged.

We checked the icon lookup with Plasma's actual task-manager library and the
standard NixOS runner, without host desktop registration. Sway rendering and
X11 `_NET_WM_ICON` checks do not prove the visible KDE taskbar result. Track that
remaining desktop check in `lllf-dt0.5.18`.

## Test the artifact

Use the [Ubuntu VM runner](architecture/control-helper-tests.md) with the
additional release directory:

```bash
bash tool/test_distro.sh /tmp/jammy.img "$checksum" \
  build/appimage-qualification --appimage build/appimage-release
```

The VM first runs the native helper checks. It then verifies artifact hashes,
opens a real Flutter window under Xvfb through FUSE and through extraction, and
uses the bundled helper from both locations for synthetic write/readback/restore.
Paths contain spaces. The acceptance guest has no GTK, JVM, or installed Legion
service. Both normal launches must display the Dashboard and map GTK, GLib,
and Pango from the AppImage. The tests press the X button and require exit status
zero. They retain screenshots, logs, and desktop memory maps. The helper must
load no shared libraries; the test also checks the bundled directory command.
The VM uses QEMU's host CPU profile with KVM, or the named 64-bit `Nehalem`
profile with software emulation. Mesa's LLVM can misidentify the generic `max`
profile as a 32-bit AMD processor. The evidence records the selected profile and
the guest's CPU information.
Test-only Polkit decisions approve the synthetic helper session. Live password
prompts remain a separate check. Persistent service, policy, and udev files must
match their state before the AppImage tests.

Test the same artifact through the NixOS launcher:

```bash
bash tool/test_appimage_nixos.sh build/appimage-release/*.AppImage build/appimage-nixos-qualification
```

This separate NixOS VM launches the actual app through official `appimage-run`.
It uses the helper on first launch and changes and restores a synthetic setting
on the Battery page. It checks private GTK libraries,
the runner's user namespace, static helper execution, cleanup, denied approval,
and a missing authentication agent. It also tests fixed-location CLI discovery
inside the runner. The synthetic CLI and kernel files exist only in the VM, and
the test touches no real hardware. CI runs both VM checks and keeps their
evidence. Tag-release preparation requires both checks for this bundled format
and verifies that they tested the same AppImage hash and source commit.

## Known shutdown issue

Historical official-SDK packages intermittently crashed on normal close in
NixOS and Ubuntu VMs. We reverted the native cleanup experiment; newer passing
acceptance does not establish a crash fix. On 17 November, the user deferred
further investigation unless a concrete cause and simple supported fix become
available. See the [shutdown evidence and stop condition](linux-shutdown.md).
Normal-close checks remain required for each release candidate.

## Desktop trial

Open the app and record the current Conservation mode value.
Change it and, if a password prompt appears, cancel first: the setting must stay
unchanged. Retry, approve, and confirm the new value in the app. Restore the
original value, confirm it, and close the app normally. Confirm that the session's
privileged control helper has stopped. Record the package hash, desktop and
X11/Wayland session, any error, and the numeric terminal exit status; expect zero.
This checks the actual driver, CLI, and desktop approval; the VM tests use
synthetic hardware and test-only approval policies.

Also check the running-app icon and window corners: restored content should be
rounded; maximized and fullscreen content should be square. Restore the window
and confirm that rounded corners return. Record these results separately from
hardware control and Dolphin's file preview.

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
new artifact and its matching checksums. On NixOS, the standard runner above
supplies the core loader and graphics libraries.

To test the separate extraction path on a compatible host, run
`--appimage-extract` and then `squashfs-root/AppRun`. Record this result separately
from FUSE launch.

## Runtime inputs

The versioned type-2 runtime `20251108` is pinned by hash. Its build source,
libfuse 3.15.0, squashfuse 0.5.2, and source/notice snapshots for its Alpine 3.21
libraries accompany the app source. The runtime build recipe and libfuse patch
remain in the upstream source archive. Upstream provides no complete manifest
of the binary's Alpine package revisions; those revisions remain unverified.

The build assembles the type-2 image from that runtime and a SquashFS payload
using Ubuntu's `mksquashfs`. See the [AppImage format](https://docs.appimage.org/reference/architecture.html),
[AppDir specification](https://docs.appimage.org/reference/appdir.html), and
[runtime build sources](https://github.com/AppImage/type2-runtime/tree/20251108).
