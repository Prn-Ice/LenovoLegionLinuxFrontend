String rebuildInstructions({required bool staticHelper}) =>
    '''# Rebuild this release

Use the SDK-reported Flutter version and framework/engine revisions in
SOURCE-MANIFEST.json. For Nix SDKs, source_provenance identifies the upstream
archive/ref, the source-tree NAR hash, derivation IDs, and distributor patches.
The NAR hash describes the unpacked tree, not the downloaded tarball bytes.
Distributor SDKs can report a placeholder framework revision; use the recorded
source provenance when available, or obtain SDK source from its distributor.
Install the Linux build dependencies listed in source/CONTRIBUTING.md.

From this archive directory:

```sh
cp dependency-overrides.yaml source/pubspec_overrides.yaml
cd source
flutter pub get
flutter build linux --release --no-pub
```

The overrides use the archived package sources, including any local edits.
The original pubspec.lock records the hosted versions; pub get replaces their
locations with these local paths. Flutter SDK source and host libraries are
obtained separately. Different compilers or system libraries can change the
rebuilt binary's checksum.
${staticHelper ? '''
This AppImage also contains distro libraries and a statically linked helper.
Their exact source packages and checksums are in
release-inputs/native/native-runtime.json; the archives are beside it under
sources/. Each .dsc and its companion archives retain the distribution patches
and build recipes. The shipped copyright notices are under
share/licenses/appimage-native/ in the app bundle. The source code above and
these library sources provide the material needed to modify and relink the
helper. Build its static dependencies on Ubuntu 22.04, then run:

```sh
bash source/tool/build_static_helper.sh source \\
  release-inputs/native/sources/util-linux/*.dsc /tmp/legion-static-rebuild \\
  source/build/linux/x64/release/bundle/libexec/legion-control-helper
```

The AppImage builder Dockerfile lists the development packages and tools.
For a modified library, rebuild its source package and install the resulting
development archive before relinking. See source/docs/appimage.md for desktop
runtime staging and the host graphics baseline.
''' : ''}
''';
