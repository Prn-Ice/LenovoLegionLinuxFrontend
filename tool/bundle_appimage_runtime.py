"""Bundle the desktop runtime and archive the exact Ubuntu package sources."""

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

# Keep the loader, C/C++ ABI and graphics drivers supplied by the host. Shipping
# older copies can prevent a newer host GPU driver from loading. GTK, GLib,
# Pango, font rendering and their remaining dependencies belong to this bundle.
HOST_LIBRARIES = {
    "ld-linux-x86-64.so.2",
    "libc.so.6",
    "libdl.so.2",
    "libm.so.6",
    "libmvec.so.1",
    "libpthread.so.0",
    "libresolv.so.2",
    "librt.so.1",
    "libutil.so.1",
    "libstdc++.so.6",
    "libgcc_s.so.1",
    "libGL.so.1",
    "libEGL.so.1",
    "libGLESv2.so.2",
    "libGLdispatch.so.0",
    "libGLX.so.0",
    "libOpenGL.so.0",
    "libdrm.so.2",
    "libgbm.so.1",
    "libglapi.so.0",
    "libX11.so.6",
    "libX11-xcb.so.1",
    "libxcb.so.1",
    "libwayland-client.so.0",
}


def run(*arguments, cwd=None, environment=None):
    env = dict(os.environ)
    for name in ("LD_LIBRARY_PATH", "LD_PRELOAD", "LD_AUDIT"):
        env.pop(name, None)
    env.update(LC_ALL="C")
    env.update(environment or {})
    return subprocess.check_output(arguments, cwd=cwd, env=env, text=True)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def elf(path):
    with path.open("rb") as source:
        return source.read(4) == b"\x7fELF"


def dependencies(output):
    result = {}
    for line in output.splitlines():
        if "=> not found" in line:
            raise ValueError("Unresolved desktop dependency: " + line.strip())
        match = re.match(r"\s*(\S+) => (/.*?) \(0x[0-9a-f]+\)", line)
        if match:
            result[match[1]] = Path(match[2])
    return result


class RuntimeBundle:
    def __init__(self, appdir, inputs):
        self.appdir = appdir
        self.bundle = appdir / "usr/lib/legion_frontend"
        self.inputs = inputs
        self.packages = {}
        self.sources = {}
        self.files = {}
        self.host_libraries = {"ld-linux-x86-64.so.2", "libEGL.so.1", "libGLESv2.so.2"}

    def package(self, name):
        if name in self.packages:
            return name
        data = run(
            "dpkg-query",
            "-W",
            "-f",
            "${binary:Package}\t${Version}\t${source:Package}\t${source:Version}",
            name,
        ).split("\t")
        binary, version, source, source_version = data
        source = source or binary.split(":")[0]
        source_version = source_version or version
        record = {
            "version": version,
            "source": source,
            "source_version": source_version,
        }
        self.packages[binary] = record
        previous = self.sources.get(source)
        if previous and previous["version"] != source_version:
            raise ValueError("Mixed source versions for " + source)
        if not previous:
            directory = self.inputs / "sources" / source
            directory.mkdir(parents=True, exist_ok=True)
            run(
                "apt-get",
                "source",
                "--download-only",
                "--only-source",
                source + "=" + source_version,
                cwd=directory,
            )
            archives = {path.name: sha256(path) for path in sorted(directory.iterdir())}
            if not archives or not list(directory.glob("*.dsc")):
                raise ValueError("Incomplete source download for " + source)
            self.sources[source] = {"version": source_version, "archives": archives}
        copyright_file = Path("/usr/share/doc") / binary.split(":")[0] / "copyright"
        if not copyright_file.is_file():
            raise ValueError("Missing copyright notice for " + binary)
        target = self.bundle / "share/licenses/appimage-native" / binary / "copyright"
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(copyright_file, target)
        return binary

    def owner(self, path):
        candidates = [str(path), str(path.resolve())]
        for candidate in list(candidates):
            if candidate.startswith("/usr/"):
                candidates.append(candidate[4:])
            elif candidate.startswith(("/lib/", "/bin/", "/sbin/")):
                candidates.append("/usr" + candidate)
        for candidate in dict.fromkeys(candidates):
            result = subprocess.run(
                ["dpkg-query", "-S", candidate],
                text=True,
                capture_output=True,
                check=False,
            )
            if result.returncode == 0:
                for line in result.stdout.splitlines():
                    package, _, owned = line.partition(": ")
                    if owned == candidate:
                        return self.package(package)
        raise ValueError("No distro source owner for " + str(path))

    def copy(self, source, target, package=None):
        package = self.package(package) if package else self.owner(source)
        if target.exists() and sha256(target) != sha256(source):
            raise ValueError("Conflicting runtime file: " + str(target))
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        target.chmod(0o755 if os.access(source, os.X_OK) else 0o644)
        self.files[str(target.relative_to(self.appdir))] = {
            "sha256": sha256(target),
            "package": package,
        }

    def closure(self, roots):
        pending = list(roots)
        seen = set()
        while pending:
            binary = pending.pop()
            if binary in seen:
                continue
            seen.add(binary)
            metadata = run("readelf", "-dW", str(binary))
            if "(NEEDED)" not in metadata:
                continue
            output = run(
                "ldd",
                str(binary),
                environment={"LD_LIBRARY_PATH": str(self.bundle / "lib")},
            )
            for name, path in dependencies(output).items():
                if name in HOST_LIBRARIES:
                    self.host_libraries.add(name)
                    continue
                target = self.bundle / "lib" / name
                if path.resolve().is_relative_to(self.appdir):
                    pending.append(path)
                    continue
                self.copy(path, target)
                pending.append(path)

    def data_package(self, package, prefix):
        self.package(package)
        copied = []
        for name in run("dpkg-query", "-L", package).splitlines():
            path = Path(name)
            if name.startswith(prefix + "/") and path.is_file():
                target = self.appdir / name.lstrip("/")
                self.copy(path, target, package)
                copied.append(target)
        if not copied:
            raise ValueError("No runtime data from " + package)
        return copied

    def static_helper(self, root):
        self.package("libmount1")
        source = next((self.inputs / "sources/util-linux").glob("*.dsc"))
        helper = self.bundle / "libexec/legion-portable-control"
        with tempfile.TemporaryDirectory(prefix="static-helper-") as build:
            log = run(
                "bash",
                str(root / "tool/build_static_helper.sh"),
                str(root),
                str(source),
                build,
                str(helper),
            )
            (self.inputs / "static-helper-build.log").write_text(log)
            cleanup = Path(build) / "helper/legion_portable_cleanup"
            if cleanup.stat().st_size >= 64 * 1024:
                raise ValueError("The embedded cleanup ELF must stay below 64 KiB")
            metadata = run("readelf", "-lW", "-dW", str(cleanup))
            if re.search(r"INTERP|\((?:NEEDED|RPATH|RUNPATH)\)", metadata):
                raise ValueError("The embedded cleanup ELF must be fully static")
            shutil.copyfile(cleanup, self.inputs / "portable-cleanup.elf")
            self.cleanup = {"sha256": sha256(cleanup), "size": cleanup.stat().st_size}
            archives = {}
            for line in log.splitlines():
                if re.fullmatch(r"/\S+\.a", line):
                    path = Path(line)
                    archives[path.name] = {
                        "sha256": sha256(path),
                        **(
                            {"source": "util-linux"}
                            if path.is_relative_to(build)
                            else {"package": self.owner(path)}
                        ),
                    }
            if "libc.a" not in archives or "libglib-2.0.a" not in archives:
                raise ValueError("The static helper link trace is incomplete")
            self.static_libraries = archives
        metadata = run("readelf", "-lW", "-dW", str(helper))
        if re.search(r"INTERP|\((?:NEEDED|RPATH|RUNPATH)\)", metadata):
            raise ValueError("The AppImage helper must be fully static")

    def finish(self):
        for source, record in self.sources.items():
            directory = self.inputs / "sources" / source
            actual = {path.name: sha256(path) for path in sorted(directory.iterdir())}
            if actual != record["archives"]:
                raise ValueError("Source archives changed during the build: " + source)
        notices = self.bundle / "share/licenses/appimage-native/common-licenses"
        shutil.copytree("/usr/share/common-licenses", notices, dirs_exist_ok=True)
        manifest = {
            "format": 1,
            "packages": self.packages,
            "sources": self.sources,
            "files": self.files,
            "host_libraries": sorted(self.host_libraries),
            "helper": {
                "linkage": "static",
                "libraries": self.static_libraries,
                "cleanup": self.cleanup,
            },
        }
        encoded = json.dumps(manifest, indent=2, sort_keys=True) + "\n"
        (self.inputs / "native-runtime.json").write_text(encoded)
        (self.bundle / "share/licenses/appimage-native/native-runtime.json").write_text(
            encoded
        )


def bundle_runtime(root, appdir, inputs):
    runtime = RuntimeBundle(appdir, inputs)
    runtime.static_helper(root)
    desktop = [
        path for path in runtime.bundle.rglob("*") if path.is_file() and elf(path)
    ]
    modules = []
    for directory in Path("/usr/lib").glob("*/gdk-pixbuf-2.0/*/loaders"):
        for source in sorted(directory.glob("*.so")):
            target = runtime.bundle / "lib/pixbuf-loaders" / source.name
            runtime.copy(source, target)
            modules.append(target)
    if not modules:
        raise ValueError("No GTK image loaders found")
    query = Path(
        run(
            "pkg-config", "--variable=gdk_pixbuf_query_loaders", "gdk-pixbuf-2.0"
        ).strip()
    )
    query_target = runtime.bundle / "libexec/gdk-pixbuf-query-loaders"
    runtime.copy(query, query_target)
    dconf = next(Path("/usr/lib").glob("*/gio/modules/libdconfsettings.so"))
    dconf_target = runtime.bundle / "lib/gio/modules/libdconfsettings.so"
    runtime.copy(dconf, dconf_target)
    runtime.closure(desktop + modules + [query_target, dconf_target])
    run("gio-querymodules", str(dconf_target.parent))
    for package in ("libgtk-3-common", "gsettings-desktop-schemas"):
        runtime.data_package(package, "/usr/share/glib-2.0/schemas")
    run("glib-compile-schemas", str(appdir / "usr/share/glib-2.0/schemas"))
    runtime.data_package("adwaita-icon-theme", "/usr/share/icons/Adwaita")
    runtime.data_package("hicolor-icon-theme", "/usr/share/icons/hicolor")
    runtime.data_package("fonts-dejavu-core", "/usr/share/fonts/truetype/dejavu")
    xdg = appdir / "usr/bin/xdg-user-dir"
    runtime.copy(Path("/usr/bin/xdg-user-dir"), xdg)
    fontconfig = appdir / "usr/etc/fonts/fonts.conf"
    fontconfig.parent.mkdir(parents=True, exist_ok=True)
    fontconfig.write_text("""<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <dir prefix="relative">../../share/fonts</dir>
  <dir>/usr/share/fonts</dir>
  <dir>/usr/local/share/fonts</dir>
  <dir prefix="xdg">fonts</dir>
  <cachedir prefix="xdg">fontconfig</cachedir>
</fontconfig>
""")
    runtime.finish()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--appdir", type=Path, required=True)
    parser.add_argument("--inputs", type=Path, required=True)
    args = parser.parse_args()
    args.inputs.mkdir(parents=True, exist_ok=True)
    bundle_runtime(
        Path(__file__).resolve().parent.parent,
        args.appdir.resolve(),
        args.inputs.resolve(),
    )


if __name__ == "__main__":
    main()
