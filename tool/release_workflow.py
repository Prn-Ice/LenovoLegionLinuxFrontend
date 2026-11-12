"""Validate tag builds and prepare GitHub release drafts from checked artifacts."""

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import tarfile
from enum import Enum
from pathlib import Path


class ReleaseCommand(Enum):
    check_tag = "check-tag"
    prepare = "prepare"
    publish = "publish"


QUALIFIED_APPIMAGE = (
    "FUSE, extraction, desktop launch, and synthetic helper control verified"
)
QUALIFIED_DEB = "install, desktop, helper, upgrade, and purge verified"


def debian_names(release):
    version, separator, build = release["version"].partition("+")
    package_version = version.replace("-", "~", 1) + separator + build + "-1"
    prefix = f"legion-frontend-{release['version']}-amd64"
    return [
        f"legion-linux-frontend_{package_version}_amd64.deb",
        prefix + "-source.tar.gz",
        prefix + ".json",
        prefix + "-acceptance.tar.gz",
    ]


def prepare_debian(release, inputs, output):
    package, source, metadata, evidence = debian_names(release)
    directory = inputs / "deb-release"
    checksums = _checksums(directory, {package, source, metadata})
    manifest = _json(directory / metadata)
    if (
        manifest["format"] != 1
        or manifest["architecture"] != "amd64"
        or manifest["version"] != release["version"]
        or manifest["package_version"]
        != package.removeprefix("legion-linux-frontend_").removesuffix("_amd64.deb")
        or manifest["source_commit"] != release["commit"]
        or manifest["portable_control"] is not True
        or manifest["default_control_mode"] != "installedService"
        or manifest["files"] != {name: checksums[name] for name in [package, source]}
    ):
        raise ValueError("The Debian build differs from the tagged portable release.")
    sources = _archived_json(directory / source, "./SOURCE-MANIFEST.json")
    if (
        sources["format"] != 4
        or sources["inputs"]["commit"] != release["commit"]
        or sources["build_config"]["portable_control"] is not True
        or sources["bundle"] != manifest["bundle"]
    ):
        raise ValueError("The Debian source companion differs from its shipped bundle.")
    for name in [
        "./legion_frontend",
        "./lib/libapp.so",
        "./libexec/legion-portable-control",
    ]:
        if manifest["bundle"].get(name, {}).get("type") != "file":
            raise ValueError(f"The Debian bundle lacks {name}.")
    for label, distribution in [
        ("ubuntu", ("ID=ubuntu", 'VERSION_ID="22.04"')),
        ("debian", ("ID=debian", 'VERSION_ID="12"')),
    ]:
        qa_directory = inputs / f"deb-{label}-qualification"
        qa = _json(qa_directory / "manifest.json")
        if (
            qa["commit"] != release["commit"]
            or qa["source_worktree_modified"] is not False
            or qa["deb"] != QUALIFIED_DEB
        ):
            raise ValueError(f"Debian package acceptance is incomplete for {label}.")
        expected = {"native-source.tar.gz", "deb-qualification.tar.gz"}
        if set(qa["files"]) != expected:
            raise ValueError("The Debian VM evidence list is incomplete.")
        for name in expected:
            if _sha256(qa_directory / name) != qa["files"][name]:
                raise ValueError(f"Debian VM evidence checksum differs: {name}")
        archive = qa_directory / "deb-qualification.tar.gz"
        if _archived_json(archive, "deb-release-manifest.json") != manifest:
            raise ValueError("The VM tested a different Debian package.")
        checks = _archived_json(archive, "deb-checks.json")
        required = {
            "installation",
            "desktop",
            "helper",
            "denied",
            "missing_agent",
            "upgrade",
            "purge",
            "existing_integration_preserved",
        }
        if set(checks) != required or any(
            value is not True for value in checks.values()
        ):
            raise ValueError("A required Debian acceptance check has not passed.")
        with tarfile.open(archive) as contents:
            os_release = (
                contents.extractfile("deb-os-release").read().decode().splitlines()
            )
        if not all(line in os_release for line in distribution):
            raise ValueError(
                "The Debian package evidence identifies the wrong distribution."
            )
    for name in [package, source, metadata]:
        shutil.copyfile(directory / name, output / name)
    with tarfile.open(output / evidence, "w:gz") as archive:
        for label in ["ubuntu", "debian"]:
            for name in [
                "manifest.json",
                "native-source.tar.gz",
                "deb-qualification.tar.gz",
                "qualification.log",
            ]:
                archive.add(
                    _file(inputs / f"deb-{label}-qualification" / name),
                    arcname=label + "/" + name,
                    recursive=False,
                )
    return [package, source, metadata, evidence]


def check_tag(root, tag):
    match = re.search(
        r"^version:[ \t]*([^\s]+)[ \t]*$",
        (root / "pubspec.yaml").read_text(),
        re.MULTILINE,
    )
    if not match or not re.fullmatch(
        r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?", match[1]
    ):
        raise ValueError("pubspec.yaml needs an unquoted release version.")
    version = match[1]
    expected_tag = "v" + version.split("+", 1)[0]
    if tag != expected_tag:
        raise ValueError(
            f"Expected tag {expected_tag} for pubspec version {version}; received {tag}."
        )
    commit = _git(root, "rev-parse", "HEAD")
    tagged_commit = _git(root, "rev-parse", "--verify", f"refs/tags/{tag}^{{commit}}")
    if commit != tagged_commit:
        raise ValueError("The checked-out commit differs from the release tag.")
    return {
        "tag": tag,
        "commit": commit,
        "version": version,
        "prerelease": "-" in expected_tag,
    }


def _git(root, *arguments):
    result = subprocess.run(
        ["git", "-C", str(root), *arguments], text=True, capture_output=True, check=True
    )
    return result.stdout.strip()


def _file(path):
    if path.is_symlink() or not path.is_file() or path.stat().st_size == 0:
        raise ValueError(
            f"Required release file is missing, empty, or a symlink: {path.name}"
        )
    return path


def _sha256(path):
    digest = hashlib.sha256()
    with _file(path).open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _json(path):
    return json.loads(_file(path).read_text())


def _checksums(directory, expected_names):
    checksums = {}
    for line in _file(directory / "SHA256SUMS").read_text().splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  ([^\r\n]+)", line)
        if not match or match[2] not in expected_names or match[2] in checksums:
            raise ValueError(
                "The release checksum file contains an unexpected or duplicate entry."
            )
        checksums[match[2]] = match[1]
    if set(checksums) != set(expected_names):
        raise ValueError("The release checksum file is incomplete.")
    for name, expected in checksums.items():
        if _sha256(directory / name) != expected:
            raise ValueError(f"Release checksum differs: {name}")
    return checksums


def _archived_json(archive, name):
    with tarfile.open(_file(archive)) as contents:
        member = contents.getmember(name)
        if not member.isfile():
            raise ValueError(f"Expected a regular archived manifest: {name}")
        return json.load(contents.extractfile(member))


def prepare(root, tag, inputs, output):
    release = check_tag(root, tag)
    prefix = f"legion-frontend-{release['version']}-x86_64"
    directory = inputs / "appimage-release"
    qa_directory = inputs / "appimage-qualification"
    image, source, metadata = (
        prefix + ".AppImage",
        prefix + "-source.tar.gz",
        prefix + ".json",
    )
    checksums = _checksums(directory, {image, source, metadata})
    manifest = _json(directory / metadata)
    if (
        manifest["format"] != 1
        or manifest["architecture"] != "x86_64"
        or manifest["portable_control"] is not True
    ):
        raise ValueError("Expected a portable Ubuntu x86-64 AppImage manifest.")
    if (
        manifest["version"] != release["version"]
        or manifest["source_commit"] != release["commit"]
    ):
        raise ValueError("The AppImage version or source commit differs from the tag.")
    if manifest["files"] != {image: checksums[image], source: checksums[source]}:
        raise ValueError("The AppImage manifest and checksums differ.")
    sources = _archived_json(directory / source, "./SOURCE-MANIFEST.json")
    if (
        sources["format"] != 4
        or sources["inputs"]["commit"] != release["commit"]
        or sources["build_config"]["portable_control"] is not True
    ):
        raise ValueError("The source companion does not describe this portable build.")
    bundle_prefix = "./usr/lib/legion_frontend"
    shipped = {
        "." + path[len(bundle_prefix) :]: entry
        for path, entry in manifest["appdir"].items()
        if path == bundle_prefix or path.startswith(bundle_prefix + "/")
    }
    if sources["bundle"] != shipped:
        raise ValueError(
            "The source manifest differs from the complete shipped bundle."
        )
    for path in [
        "./legion_frontend",
        "./lib/libapp.so",
        "./libexec/legion-portable-control",
    ]:
        if shipped.get(path, {}).get("type") != "file":
            raise ValueError(f"The shipped bundle lacks {path}.")
    qa = _json(qa_directory / "manifest.json")
    if qa["commit"] != release["commit"] or qa["source_worktree_modified"] is not False:
        raise ValueError(
            "VM qualification used a different or modified source checkout."
        )
    if qa["appimage"] != QUALIFIED_APPIMAGE:
        raise ValueError("AppImage VM acceptance has not passed.")
    qa_files = {"native-source.tar.gz", "appimage-qualification.tar.gz"}
    if set(qa["files"]) != qa_files:
        raise ValueError("The VM evidence file list is incomplete.")
    for name in qa_files:
        if _sha256(qa_directory / name) != qa["files"][name]:
            raise ValueError(f"VM evidence checksum differs: {name}")
    tested = _archived_json(
        qa_directory / "appimage-qualification.tar.gz", "appimage-release-manifest.json"
    )
    if tested != manifest:
        raise ValueError("The VM tested different release artifacts.")
    if output.exists():
        raise ValueError("Release output already exists.")
    output.mkdir(parents=True)
    assets = [image, source, metadata, prefix + "-acceptance.tar.gz"]
    for name in assets[:3]:
        shutil.copyfile(directory / name, output / name)
    with tarfile.open(output / assets[3], "w:gz") as archive:
        for name in [
            "manifest.json",
            "native-source.tar.gz",
            "appimage-qualification.tar.gz",
            "qualification.log",
        ]:
            archive.add(_file(qa_directory / name), arcname=name, recursive=False)
    assets.extend(prepare_debian(release, inputs, output))
    (output / "SHA256SUMS").write_text(
        "".join(f"{_sha256(output / name)}  {name}\n" for name in assets)
    )
    assets.append("SHA256SUMS")
    notes = output / "RELEASE-NOTES.md"
    notes.write_text(f"""Ubuntu x86-64 AppImage and Debian amd64 package built from `{tag}` (`{release["commit"]}`).

FUSE launch, extracted launch, and the bundled temporary helper passed the Ubuntu
VM checks with a synthetic CLI. Real laptop hardware, actual CLI dependencies,
and desktop password prompts still need qualification.

The Debian package passed install, desktop launch, synthetic helper control,
denied approval, missing-agent, upgrade, and purge checks on Ubuntu 22.04 and
Debian 12. Existing integration files were preserved.

Hardware control requires the LenovoLegionLinux driver, an administrator-owned
legion_cli installation, systemd, and a desktop authentication agent. Choose
Temporary helper in Settings and reopen the app to use portable control.

Each artifact has a matching source companion, build manifest, and VM evidence.
Verify SHA256SUMS before using the files.
""")
    plan = dict(
        release,
        assets={name: _sha256(output / name) for name in assets},
        notes_sha256=_sha256(notes),
    )
    (output / "release-plan.json").write_text(json.dumps(plan, indent=2) + "\n")
    return plan


def _github_api(path):
    result = subprocess.run(
        ["gh", "api", "--include", path],
        check=False,
        text=True,
        capture_output=True,
        timeout=60,
    )
    response = result.stdout.replace("\r\n", "\n")
    headers, separator, body = response.partition("\n\n")
    status = re.match(r"HTTP/\S+ (\d{3})", headers)
    if status and status[1] == "404":
        return None
    if result.returncode or not status or status[1] != "200" or not separator:
        raise RuntimeError("GitHub lookup failed: " + result.stderr.strip())
    return json.loads(body)


def _github_command(arguments):
    subprocess.run(["gh", *arguments], check=True, timeout=300)


def _remote_commit(repository, tag):
    reference = _github_api(f"repos/{repository}/git/ref/tags/{tag}")
    if reference is None:
        raise ValueError("The release tag is missing from GitHub.")
    target = reference["object"]
    for _ in range(10):
        if target["type"] == "commit":
            return target["sha"]
        if target["type"] != "tag":
            break
        annotation = _github_api(f"repos/{repository}/git/tags/{target['sha']}")
        if annotation is None:
            break
        target = annotation["object"]
    raise ValueError("The remote release tag does not resolve to a commit.")


def _find_release(repository, tag):
    # Listing includes drafts for the release job's authenticated writer.
    for page in range(1, 101):
        releases = _github_api(f"repos/{repository}/releases?per_page=100&page={page}")
        if not isinstance(releases, list):
            raise TypeError("GitHub did not return the repository releases.")
        for release in releases:
            if release["tag_name"] == tag:
                return release
        if len(releases) < 100:
            return None
    raise RuntimeError("Release lookup exceeded 100 pages.")


def publish(root, tag, output, repository):
    release = check_tag(root, tag)
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Expected an owner/repository name.")
    plan = _json(output / "release-plan.json")
    for key, value in release.items():
        if plan[key] != value:
            raise ValueError("The prepared release differs from this tag.")
    prefix = f"legion-frontend-{release['version']}-x86_64"
    expected = {
        prefix + ".AppImage",
        prefix + "-source.tar.gz",
        prefix + ".json",
        prefix + "-acceptance.tar.gz",
        "SHA256SUMS",
    }
    expected.update(debian_names(release))
    if set(plan["assets"]) != expected:
        raise ValueError("The prepared release asset list differs.")
    for name, digest in plan["assets"].items():
        if _sha256(output / name) != digest:
            raise ValueError(f"Prepared release asset changed: {name}")
    notes = output / "RELEASE-NOTES.md"
    if _sha256(notes) != plan["notes_sha256"]:
        raise ValueError("Prepared release notes changed.")
    if _remote_commit(repository, tag) != release["commit"]:
        raise ValueError("The GitHub tag moved after the build.")
    existing = _find_release(repository, tag)
    if existing is not None and existing["draft"] is not True:
        raise ValueError(
            "This tag already has a published release; its assets are protected."
        )
    operation = "create" if existing is None else "edit"
    command = [
        "release",
        operation,
        tag,
        "--repo",
        repository,
        "--title",
        tag,
        "--notes-file",
        str(notes),
        f"--prerelease={str(release['prerelease']).lower()}",
    ]
    if existing is None:
        command += ["--draft", "--verify-tag", "--target", release["commit"]]
    _github_command(command)
    _github_command(
        [
            "release",
            "upload",
            tag,
            "--repo",
            repository,
            "--clobber",
            *[str(output / name) for name in plan["assets"]],
        ]
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    check = commands.add_parser(ReleaseCommand.check_tag.value)
    check.add_argument("tag")
    prepare_command = commands.add_parser(ReleaseCommand.prepare.value)
    prepare_command.add_argument("tag")
    prepare_command.add_argument("inputs", type=Path)
    prepare_command.add_argument("output", type=Path)
    publish_command = commands.add_parser(ReleaseCommand.publish.value)
    publish_command.add_argument("tag")
    publish_command.add_argument("output", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    try:
        command = ReleaseCommand(args.command)
        if command is ReleaseCommand.check_tag:
            release = check_tag(root, args.tag)
            if os.environ.get("GITHUB_OUTPUT"):
                with Path(os.environ["GITHUB_OUTPUT"]).open("a") as output:
                    output.write(f"tag={release['tag']}\ncommit={release['commit']}\n")
            print(json.dumps(release))
        elif command is ReleaseCommand.prepare:
            print(json.dumps(prepare(root, args.tag, args.inputs, args.output)))
        else:
            publish(
                root, args.tag, args.output, os.environ.get("GITHUB_REPOSITORY", "")
            )
    except (
        OSError,
        ValueError,
        RuntimeError,
        KeyError,
        TypeError,
        tarfile.TarError,
        subprocess.SubprocessError,
    ) as error:
        parser.exit(1, f"Release: {error}\n")


if __name__ == "__main__":
    main()
