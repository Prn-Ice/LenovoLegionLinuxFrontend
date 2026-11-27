# Distribution Packaging

Distribution-specific build definitions and runtime metadata live here,
separate from the Flutter Linux runner in [`linux/`](../linux/).

## Subdirectories

- [`appimage/`](appimage/) — Desktop entry, AppStream metadata, `AppRun`,
  Docker builder definition, and pinned runtime inputs. See
  [the AppImage guide](../docs/appimage.md).
- [`debian/`](debian/) — Launcher wrapper, maintainer scripts, and systemd
  graphics service unit. See [the Debian guide](../docs/debian.md).
- [`nix/`](nix/) — Nix derivations for the Flutter frontend, static helper,
  and AppImage, plus synced JSON manifests. See
  [the Nix guide](../docs/nix.md).
