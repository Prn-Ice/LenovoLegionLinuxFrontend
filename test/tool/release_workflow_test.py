"""Exercise release validation and GitHub writes with local files and fake API replies."""

import importlib.util
import io
import json
import os
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest import mock

spec = importlib.util.spec_from_file_location(
    "release_workflow", Path(__file__).resolve().parents[2] / "tool/release_workflow.py"
)
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


def archive_json(path, name, value, additional=None):
    with tarfile.open(path, "w:gz") as archive:
        for filename, contents in {name: value, **(additional or {})}.items():
            data = json.dumps(contents).encode()
            info = tarfile.TarInfo(filename)
            info.size = len(data)
            archive.addfile(info, io.BytesIO(data))


class ReleaseWorkflowTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="release with spaces ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "source"
        self.root.mkdir()
        self.git("init", "-q", "--initial-branch=main")
        self.git("config", "user.name", "Release test")
        self.git("config", "user.email", "release@example.invalid")
        (self.root / "pubspec.yaml").write_text("name: fixture\nversion: 1.2.3+7\n")
        self.git("add", ".")
        self.git("commit", "-qm", "fixture")
        self.commit = self.git("rev-parse", "HEAD").strip()
        self.tag = "v1.2.3"
        self.git("tag", "-a", self.tag, "-m", "fixture release")
        self.inputs = Path(self.temporary.name) / "inputs"
        self.binary = self.inputs / "appimage-release"
        self.qa = self.inputs / "appimage-qualification"
        self.binary.mkdir(parents=True)
        self.qa.mkdir()
        self.output = Path(self.temporary.name) / "prepared"
        self.prefix = "legion-frontend-1.2.3+7-x86_64"
        self.image = self.prefix + ".AppImage"
        self.source = self.prefix + "-source.tar.gz"
        self.metadata = self.prefix + ".json"
        (self.binary / self.image).write_bytes(b"AppImage fixture")
        bundle = {
            ".": {"type": "directory", "mode": "755"},
            "./legion_frontend": {"type": "file", "mode": "755", "sha256": "b" * 64},
            "./lib/libapp.so": {"type": "file", "mode": "644", "sha256": "c" * 64},
            "./libexec/legion-portable-control": {
                "type": "file",
                "mode": "755",
                "sha256": "a" * 64,
            },
        }
        self.sources = {
            "format": 4,
            "inputs": {"commit": self.commit},
            "build_config": {"portable_control": True},
            "bundle": bundle,
        }
        archive_json(self.binary / self.source, "./SOURCE-MANIFEST.json", self.sources)
        self.manifest = {
            "format": 1,
            "version": "1.2.3+7",
            "source_commit": self.commit,
            "architecture": "x86_64",
            "portable_control": True,
            "appdir": {
                "./usr/lib/legion_frontend" + path[1:]: entry
                for path, entry in bundle.items()
            },
        }
        self.refresh()
        self.refresh_debian()

    def refresh_debian(self):
        self.deb = self.inputs / "deb-release"
        self.deb.mkdir(exist_ok=True)
        package, source, metadata, _ = release.debian_names({"version": "1.2.3+7"})
        (self.deb / package).write_bytes(b"Debian package fixture")
        archive_json(self.deb / source, "./SOURCE-MANIFEST.json", self.sources)
        self.deb_manifest = {
            "format": 1,
            "version": "1.2.3+7",
            "package_version": "1.2.3+7-1",
            "architecture": "amd64",
            "source_commit": self.commit,
            "portable_control": True,
            "default_control_mode": "installedService",
            "bundle": self.sources["bundle"],
            "files": {
                name: release._sha256(self.deb / name) for name in [package, source]
            },
        }
        (self.deb / metadata).write_text(json.dumps(self.deb_manifest))
        (self.deb / "SHA256SUMS").write_text(
            "".join(
                f"{release._sha256(self.deb / name)}  {name}\n"
                for name in [package, source, metadata]
            )
        )
        for label, os_release in [
            ("ubuntu", 'ID=ubuntu\nVERSION_ID="22.04"\n'),
            ("debian", 'ID=debian\nVERSION_ID="12"\n'),
        ]:
            directory = self.inputs / f"deb-{label}-qualification"
            directory.mkdir(exist_ok=True)
            with tarfile.open(
                directory / "deb-qualification.tar.gz", "w:gz"
            ) as archive:
                for name, value in {
                    "deb-release-manifest.json": json.dumps(self.deb_manifest),
                    "deb-os-release": os_release,
                    "deb-checks.json": json.dumps(
                        {
                            name: True
                            for name in [
                                "installation",
                                "desktop",
                                "helper",
                                "denied",
                                "missing_agent",
                                "upgrade",
                                "purge",
                                "existing_integration_preserved",
                            ]
                        }
                    ),
                }.items():
                    data = value.encode()
                    entry = tarfile.TarInfo(name)
                    entry.size = len(data)
                    archive.addfile(entry, io.BytesIO(data))
            (directory / "native-source.tar.gz").write_bytes(
                b"Debian VM source fixture"
            )
            (directory / "qualification.log").write_text("PASS: package VM checks\n")
            (directory / "manifest.json").write_text(
                json.dumps(
                    {
                        "commit": self.commit,
                        "source_worktree_modified": False,
                        "deb": release.QUALIFIED_DEB,
                        "files": {
                            name: release._sha256(directory / name)
                            for name in [
                                "native-source.tar.gz",
                                "deb-qualification.tar.gz",
                            ]
                        },
                    }
                )
            )

    def git(self, *arguments):
        return subprocess.check_output(
            ["git", "-C", str(self.root), *arguments], text=True, stderr=subprocess.PIPE
        )

    def refresh(self):
        self.manifest["files"] = {
            name: release._sha256(self.binary / name)
            for name in [self.image, self.source]
        }
        (self.binary / self.metadata).write_text(json.dumps(self.manifest))
        (self.binary / "SHA256SUMS").write_text(
            "".join(
                f"{release._sha256(self.binary / name)}  {name}\n"
                for name in [self.image, self.source, self.metadata]
            )
        )
        archive_json(
            self.qa / "appimage-qualification.tar.gz",
            "appimage-release-manifest.json",
            self.manifest,
        )
        (self.qa / "native-source.tar.gz").write_bytes(b"native source fixture")
        (self.qa / "qualification.log").write_text(
            "PASS: synthetic helper and desktop launch\n"
        )
        self.evidence = {
            "commit": self.commit,
            "source_worktree_modified": False,
            "appimage": release.QUALIFIED_APPIMAGE,
            "files": {
                name: release._sha256(self.qa / name)
                for name in ["native-source.tar.gz", "appimage-qualification.tar.gz"]
            },
        }
        (self.qa / "manifest.json").write_text(json.dumps(self.evidence))

    def prepare(self):
        return release.prepare(self.root, self.tag, self.inputs, self.output)

    def enable_native_runtime(self):
        library = "usr/lib/legion_frontend/lib/libgtk-3.so.0"
        entry = {"type": "file", "mode": "644", "sha256": "d" * 64}
        self.manifest["appdir"]["./" + library] = entry
        self.sources["bundle"]["./lib/libgtk-3.so.0"] = entry
        self.sources["build_config"]["static_portable_helper"] = True
        native = {
            "format": 1,
            "files": {library: {"sha256": "d" * 64, "package": "gtk"}},
            "packages": {"gtk": {"source": "gtk", "source_version": "1"}},
            "sources": {"gtk": {"version": "1", "archives": {"gtk.tar.xz": "e" * 64}}},
            "helper": {
                "linkage": "static",
                "cleanup": {"size": 4096, "sha256": "f" * 64},
            },
        }
        self.sources["release_inputs"] = {
            "./native/sources/gtk/gtk.tar.xz": {"sha256": "e" * 64},
            "./native/portable-cleanup.elf": {"sha256": "f" * 64},
        }
        self.manifest["native_runtime"] = native
        archive_json(
            self.binary / self.source,
            "./SOURCE-MANIFEST.json",
            self.sources,
            {"./release-inputs/native/native-runtime.json": native},
        )
        self.refresh()
        self.refresh_debian()

    def add_nixos_evidence(self, image_sha256=None):
        name = "appimage-nixos-qualification.tar.gz"
        archive_json(
            self.qa / name,
            "manifest.json",
            {
                "commit": self.commit,
                "appimage_sha256": image_sha256
                or release._sha256(self.binary / self.image),
                "nixos": "host-namespace desktop and static helper control verified",
            },
        )
        self.evidence["files"][name] = release._sha256(self.qa / name)
        (self.qa / "manifest.json").write_text(json.dumps(self.evidence))

    def test_bundled_native_runtime_requires_nixos_acceptance(self):
        self.enable_native_runtime()
        with self.assertRaisesRegex(ValueError, "evidence file list"):
            self.prepare()

    def test_static_build_cannot_omit_native_runtime_metadata(self):
        self.enable_native_runtime()
        del self.manifest["native_runtime"]
        self.refresh()
        with self.assertRaisesRegex(ValueError, "lacks its native runtime"):
            self.prepare()

    def test_native_sources_and_both_host_checks_are_retained(self):
        self.enable_native_runtime()
        self.add_nixos_evidence()
        plan = self.prepare()
        evidence = next(
            name for name in plan["assets"] if name.endswith("acceptance.tar.gz")
        )
        with tarfile.open(self.output / evidence) as archive:
            self.assertIn("appimage-nixos-qualification.tar.gz", archive.getnames())

    def test_nixos_acceptance_cannot_qualify_another_appimage(self):
        self.enable_native_runtime()
        self.add_nixos_evidence("f" * 64)
        with self.assertRaisesRegex(ValueError, "NixOS acceptance"):
            self.prepare()

    def test_runtime_library_must_match_the_shipped_file(self):
        self.enable_native_runtime()
        self.manifest["native_runtime"]["files"][
            "usr/lib/legion_frontend/lib/libgtk-3.so.0"
        ]["sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "shipped file"):
            release.validate_appimage_runtime(
                self.manifest, self.sources, self.manifest["native_runtime"]
            )

    def test_native_library_source_archive_cannot_be_omitted(self):
        self.enable_native_runtime()
        del self.sources["release_inputs"]["./native/sources/gtk/gtk.tar.xz"]
        with self.assertRaisesRegex(ValueError, "exact native archive"):
            release.validate_appimage_runtime(
                self.manifest, self.sources, self.manifest["native_runtime"]
            )

    def test_base_tag_matches_pubspec_build_number_and_annotated_commit(self):
        metadata = release.check_tag(self.root, self.tag)
        self.assertEqual(metadata["version"], "1.2.3+7")
        self.assertEqual(metadata["commit"], self.commit)
        self.assertFalse(metadata["prerelease"])

    def test_mismatched_or_shell_like_tag_is_rejected(self):
        for tag in ["v1.2.4", "v1.2.3+7", "v1.2.3; touch owned"]:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                release.check_tag(self.root, tag)
        self.assertFalse((self.root / "owned").exists())

    def test_prerelease_version(self):
        (self.root / "pubspec.yaml").write_text("version: 1.2.3-rc.1+7\n")
        self.git("commit", "-qam", "prerelease")
        self.git("tag", "v1.2.3-rc.1")
        self.assertTrue(release.check_tag(self.root, "v1.2.3-rc.1")["prerelease"])

    def test_check_tag_writes_the_validated_github_outputs(self):
        output = Path(self.temporary.name) / "github-output"
        with (
            mock.patch.object(
                release, "__file__", str(self.root / "tool/release_workflow.py")
            ),
            mock.patch("sys.argv", ["release_workflow.py", "check-tag", self.tag]),
            mock.patch.dict(os.environ, {"GITHUB_OUTPUT": str(output)}),
            mock.patch("sys.stdout", new_callable=io.StringIO),
        ):
            release.main()
        self.assertEqual(output.read_text(), f"tag={self.tag}\ncommit={self.commit}\n")

    def test_advanced_main_cannot_be_released_as_the_old_tag(self):
        (self.root / "README.md").write_text("newer main")
        self.git("add", ".")
        self.git("commit", "-qm", "newer main")
        with self.assertRaisesRegex(ValueError, "checked-out commit"):
            release.check_tag(self.root, self.tag)

    def test_detached_tag_clone_builds_tagged_source_when_main_is_newer(self):
        (self.root / "README.md").write_text("newer main")
        self.git("add", ".")
        self.git("commit", "-qm", "newer main")
        self.git("checkout", "--detach", self.tag)
        copied = Path(self.temporary.name) / "container source"
        subprocess.run(
            [
                "git",
                "clone",
                "-q",
                "--depth",
                "1",
                "--no-local",
                "--single-branch",
                self.root.as_uri(),
                str(copied),
            ],
            check=True,
            capture_output=True,
        )
        self.assertEqual(release.check_tag(copied, self.tag)["commit"], self.commit)

    def test_prepares_complete_assets_checksums_and_qualification_notes(self):
        plan = self.prepare()
        self.assertEqual(len(plan["assets"]), 9)
        checksums = release._checksums(
            self.output, set(plan["assets"]) - {"SHA256SUMS"}
        )
        self.assertEqual(
            checksums[self.image], release._sha256(self.binary / self.image)
        )
        notes = (self.output / "RELEASE-NOTES.md").read_text()
        self.assertIn("synthetic CLI", notes)
        self.assertIn("password prompts still need qualification", notes)
        self.assertIn(self.commit, notes)
        with tarfile.open(
            self.output / (self.prefix + "-acceptance.tar.gz")
        ) as archive:
            self.assertIn("appimage-qualification.tar.gz", archive.getnames())

    def test_missing_debian_acceptance_stops_the_draft(self):
        (self.inputs / "deb-debian-qualification/manifest.json").unlink()
        with self.assertRaises(ValueError):
            self.prepare()

    def test_modified_debian_package_is_rejected(self):
        package, _, _, _ = release.debian_names({"version": "1.2.3+7"})
        (self.deb / package).write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "checksum differs"):
            self.prepare()

    def test_debian_acceptance_must_match_the_package(self):
        directory = self.inputs / "deb-debian-qualification"
        self.refresh_debian()
        archive_json(
            directory / "deb-qualification.tar.gz", "deb-release-manifest.json", {}
        )
        evidence = json.loads((directory / "manifest.json").read_text())
        evidence["files"]["deb-qualification.tar.gz"] = release._sha256(
            directory / "deb-qualification.tar.gz"
        )
        (directory / "manifest.json").write_text(json.dumps(evidence))
        with self.assertRaisesRegex(ValueError, "different Debian package"):
            self.prepare()

    def replace_debian_evidence(self, member, value):
        directory = self.inputs / "deb-debian-qualification"
        path = directory / "deb-qualification.tar.gz"
        with tarfile.open(path) as archive:
            files = {
                entry.name: archive.extractfile(entry).read()
                for entry in archive.getmembers()
            }
        files[member] = value
        with tarfile.open(path, "w:gz") as archive:
            for name, data in files.items():
                entry = tarfile.TarInfo(name)
                entry.size = len(data)
                archive.addfile(entry, io.BytesIO(data))
        evidence = json.loads((directory / "manifest.json").read_text())
        evidence["files"][path.name] = release._sha256(path)
        (directory / "manifest.json").write_text(json.dumps(evidence))

    def test_debian_acceptance_requires_the_declared_distribution(self):
        self.replace_debian_evidence(
            "deb-os-release", b'ID=ubuntu\nVERSION_ID="22.04"\n'
        )
        with self.assertRaisesRegex(ValueError, "wrong distribution"):
            self.prepare()

    def test_failed_debian_purge_check_stops_the_draft(self):
        checks = {
            name: True
            for name in [
                "installation",
                "desktop",
                "helper",
                "denied",
                "missing_agent",
                "upgrade",
                "purge",
                "existing_integration_preserved",
            ]
        }
        checks["purge"] = False
        self.replace_debian_evidence("deb-checks.json", json.dumps(checks).encode())
        with self.assertRaisesRegex(ValueError, "has not passed"):
            self.prepare()

    def test_corrupted_image_is_rejected_before_output(self):
        (self.binary / self.image).write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "checksum differs"):
            self.prepare()
        self.assertFalse(self.output.exists())

    def test_source_companion_must_include_the_complete_helper_inventory(self):
        self.sources["bundle"].pop("./libexec/legion-portable-control")
        archive_json(self.binary / self.source, "./SOURCE-MANIFEST.json", self.sources)
        self.refresh()
        with self.assertRaisesRegex(ValueError, "complete shipped bundle"):
            self.prepare()

    def test_dirty_or_unqualified_vm_evidence_is_rejected(self):
        for changes in [
            {"source_worktree_modified": True},
            {"appimage": "unverified"},
            {"commit": "0" * 40},
        ]:
            with self.subTest(changes=changes):
                (self.qa / "manifest.json").write_text(
                    json.dumps(dict(self.evidence, **changes))
                )
                with self.assertRaises(ValueError):
                    self.prepare()

    def test_qualification_must_identify_the_same_release(self):
        tested = dict(self.manifest, source_commit="0" * 40)
        archive_json(
            self.qa / "appimage-qualification.tar.gz",
            "appimage-release-manifest.json",
            tested,
        )
        self.evidence["files"]["appimage-qualification.tar.gz"] = release._sha256(
            self.qa / "appimage-qualification.tar.gz"
        )
        (self.qa / "manifest.json").write_text(json.dumps(self.evidence))
        with self.assertRaisesRegex(ValueError, "different release artifacts"):
            self.prepare()

    def test_asset_symlink_is_rejected(self):
        image = self.binary / self.image
        image.unlink()
        image.symlink_to(self.root / "pubspec.yaml")
        with self.assertRaisesRegex(ValueError, "symlink"):
            self.prepare()

    def api(self, path, existing=None, target=None):
        if "/git/ref/tags/" in path:
            return {"object": {"type": "tag", "sha": "annotated-object"}}
        if "/git/tags/" in path:
            return {"object": {"type": "commit", "sha": target or self.commit}}
        return [] if existing is None else [existing]

    def test_creates_only_a_draft_with_an_existing_tag_and_all_assets(self):
        self.prepare()
        with (
            mock.patch.object(release, "_github_api", side_effect=self.api),
            mock.patch.object(release, "_github_command") as write,
        ):
            release.publish(self.root, self.tag, self.output, "owner/repository")
        create, upload = [call.args[0] for call in write.call_args_list]
        self.assertIn("--draft", create)
        self.assertIn("--verify-tag", create)
        self.assertIn(self.commit, create)
        self.assertIn("--repo", create)
        self.assertEqual(upload[:2], ["release", "upload"])
        self.assertEqual(
            len(
                [
                    argument
                    for argument in upload
                    if argument.startswith(str(self.output))
                ]
            ),
            9,
        )

    def test_rerun_refreshes_an_existing_draft(self):
        self.prepare()
        existing = {"tag_name": self.tag, "draft": True}
        with (
            mock.patch.object(
                release,
                "_github_api",
                side_effect=lambda path: self.api(path, existing),
            ),
            mock.patch.object(release, "_github_command") as write,
        ):
            release.publish(self.root, self.tag, self.output, "owner/repository")
        self.assertEqual(write.call_args_list[0].args[0][:2], ["release", "edit"])
        self.assertIn("--clobber", write.call_args_list[1].args[0])

    def test_finds_a_draft_beyond_the_first_release_page(self):
        older = [{"tag_name": f"v0.0.{index}", "draft": False} for index in range(100)]
        draft = {"tag_name": self.tag, "draft": True}
        with mock.patch.object(
            release, "_github_api", side_effect=[older, [draft]]
        ) as lookup:
            self.assertEqual(release._find_release("owner/repository", self.tag), draft)
        self.assertEqual(lookup.call_count, 2)

    def test_published_release_and_moved_remote_tag_block_writes(self):
        self.prepare()
        for existing, target in [
            ({"tag_name": self.tag, "draft": False}, self.commit),
            (None, "0" * 40),
        ]:
            with (
                self.subTest(existing=existing, target=target),
                mock.patch.object(
                    release,
                    "_github_api",
                    side_effect=lambda path, existing=existing, target=target: self.api(
                        path, existing, target
                    ),
                ),
                mock.patch.object(release, "_github_command") as write,
            ):
                with self.assertRaises(ValueError):
                    release.publish(
                        self.root, self.tag, self.output, "owner/repository"
                    )
                write.assert_not_called()

    def test_changed_prepared_asset_blocks_all_network_calls(self):
        self.prepare()
        (self.output / self.image).write_bytes(b"changed")
        with (
            mock.patch.object(release, "_github_api") as lookup,
            self.assertRaisesRegex(ValueError, "asset changed"),
        ):
            release.publish(self.root, self.tag, self.output, "owner/repository")
        lookup.assert_not_called()

    def test_api_status_handling_distinguishes_missing_and_failed_requests(self):
        cases = [
            (0, 'HTTP/2.0 200 OK\r\nHeader: value\r\n\r\n{"ok":true}', {"ok": True}),
            (1, "HTTP/2.0 404 Not Found\nHeader: value\n\n{}", None),
        ]
        for code, stdout, expected in cases:
            with mock.patch.object(
                release.subprocess,
                "run",
                return_value=subprocess.CompletedProcess([], code, stdout, ""),
            ):
                self.assertEqual(release._github_api("endpoint"), expected)
        with (
            mock.patch.object(
                release.subprocess,
                "run",
                return_value=subprocess.CompletedProcess(
                    [], 1, "HTTP/2.0 403 Forbidden\n\n{}", "forbidden"
                ),
            ),
            self.assertRaises(RuntimeError),
        ):
            release._github_api("endpoint")


if __name__ == "__main__":
    unittest.main()
