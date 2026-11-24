# Debian package

The amd64 `.deb` installs the desktop app, privileged control helper, launcher,
icons, and notices. It uses host GTK, GLib, Polkit, graphics, and C/C++ libraries.
The package also installs the one-shot command that applies iGPU-only before sign-in.

Install the package with apt so it resolves the runtime dependencies:

```bash
sudo apt install ./legion-linux-frontend_0.1.0-alpha.2+1-1_amd64.deb
legion_frontend
```

Hardware control requires the Lenovo Legion driver and an administrator-owned
`legion_cli` installation, systemd, Polkit, and a desktop authentication agent.
The app uses the bundled privileged control helper from its first launch. The
first privileged action requests approval; closing the app ends the helper session.
With a compatible `legion_cli` and laptop, choose **Integrated graphics only** on
the **Discrete GPU** page, then restart. Check the selected graphics mode and
NVIDIA status after signing in. [Driver CLI with boot support](https://github.com/Prn-Ice/LenovoLegionLinux/commit/3492884b83c4fb626cba4e4ddc32b3ef3dcc5f70)

## Build

The builder needs Docker, Git, jq, and curl. It compiles as an ordinary
user in the pinned Ubuntu 22.04 container used for AppImage builds. Build from
a clean committed checkout:

```bash
curl -fL https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.50.0-stable.tar.xz -o /tmp/flutter-3.50.0.tar.xz
bash tool/build_deb.sh /tmp/flutter-3.50.0.tar.xz build/deb-release
```

The script verifies the SDK checksum in `packaging/appimage/build-inputs.json`.
It produces the `.deb`, versioned source companion, build manifest, and
`SHA256SUMS`. Keep these together. The manifest binds every bundled file to its
source companion. The source archive contains runtime Dart package sources,
notices, and rebuild instructions; the SDK is obtained separately using its
recorded version and hashes.

The builder also creates `vm-fixtures.tar.gz` for CI acceptance. Its two
synthetic executables run only in a marked disposable VM; they are excluded
from the installed package and GitHub release assets. The build manifest records
their archive hash. Building them beside the app keeps compilers out of the
installation VMs.

The package keeps Flutter's private layout in `/usr/lib/legion_frontend`, with
the helper beside the actual desktop executable. A launcher in `/usr/bin`
executes that desktop. `dpkg-shlibdeps` calculates linked-library dependencies;
graphics libraries loaded at runtime, desktop schemas, and `xdg-user-dirs` are
listed explicitly. The app uses `xdg-user-dir` to find its settings directory.
See the [Debian dependency tool](https://manpages.debian.org/bookworm/dpkg-dev/dpkg-shlibdeps.1.en.html).

App versions map to Debian versions with a `-1` package revision. Prereleases
use Debian's `~` ordering: `1.1.0-rc.1+2` becomes `1.1.0~rc.1+2-1`.
Download filenames use `-` in place of `~` because GitHub renames tildes on
upload. The version inside the package retains `~`; apt uses that metadata for
upgrade ordering.

## Qualification

The disposable Ubuntu 22.04 and Debian 12 checks install through apt, render
the first Flutter frame, exercise synthetic helper write/readback/restore,
upgrade the package, and purge it. They compare persistent integration files
throughout. The guests have no Legion driver or JVM. Real hardware and desktop
password dialogs need separate testing.

CI runs this build and both VMs for relevant PR changes and every release tag,
not again on merge. Tag releases include the checked package and its source,
manifest, and acceptance evidence in the release.

Remove the package with:

```bash
sudo apt purge legion-linux-frontend
```

Removal deletes the package's startup files. It cancels a pending graphics
switch if this package was the last source of boot support. To return to
Hybrid after iGPU-only has taken effect, select Hybrid before uninstalling or
run `sudo legion_cli graphics-mode set hybrid`.
