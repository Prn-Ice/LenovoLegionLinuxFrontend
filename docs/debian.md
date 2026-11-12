# Debian package

The amd64 `.deb` installs the desktop app, temporary helper, launcher, icons,
and notices. It uses host GTK, GLib, Polkit, graphics, and C/C++ libraries.
Installing it adds no persistent Legion service or authorization policy.

Install the package with apt so it resolves the runtime dependencies:

```bash
sudo apt install ./legion-linux-frontend_1.0.0+1-1_amd64.deb
legion_frontend
```

Hardware control requires the Lenovo Legion driver and an administrator-owned
`legion_cli` installation. Temporary helper mode also needs systemd, Polkit,
and a desktop authentication agent. Installed service remains the default;
choose **Temporary helper** in Settings and reopen the app to use it.
Existing installed services remain separately managed.

## Build

The builder needs Docker, Git, Python 3, and curl. It compiles as an ordinary
user in the pinned Ubuntu 22.04 container used for AppImage builds. Build from
a clean committed checkout:

```bash
curl -fL https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.9-stable.tar.xz -o /tmp/flutter-3.47.9.tar.xz
bash tool/build_deb.sh /tmp/flutter-3.47.9.tar.xz build/deb-release
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

## Qualification

The disposable Ubuntu 22.04 and Debian 12 checks install through apt, render
the first Flutter frame, exercise synthetic helper write/readback/restore,
upgrade the package, and purge it. They compare persistent integration files
throughout. The guests have no Legion driver or JVM. Real hardware and desktop
password dialogs need separate testing.

CI runs this build and both VMs for relevant PR changes, every push to main,
and release tags. Future tag releases include the checked package and its
source, manifest, and acceptance evidence in the draft.

Remove the package with:

```bash
sudo apt purge legion-linux-frontend
```

User settings remain in the user's data directory after removal.
