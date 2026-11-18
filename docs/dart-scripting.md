# Dart scripting benchmark

Use [`tool/package_release.dart`](../tool/package_release.dart) and its
[`release_source`](../tool/release_source/) operations as the readability benchmark
for Dart scripts. This is a refactor of the existing release packager, verified
against its previous implementation. It is a readability example, not a
performance benchmark.

## Make the entrypoint tell the story

The release command parses its destination, builds the app, packages matching
sources, and reports the result:

```dart
Future<void> main(List<String> arguments) async {
  try {
    final root = File.fromUri(Platform.script).parent.parent;
    final archive = releaseSourceArchive(arguments, root);
    final release = await buildLinuxRelease(root);
    await packageReleaseSource(root, release.bundle, archive, release.record);
    stdout.writeln('Packaged release source: ${archive.path}');
  } catch (error) {
    stderr.writeln('Release source: $error');
    exitCode = error is FormatException ? 64 : 1;
  }
}
```

Keep asynchronous completion visible. Parsing, the successful path, and failure
status belong in the entrypoint; command arguments and archive mechanics belong
with the operation that owns them.

## Real before and after

Before this refactor, `buildLinuxRelease` exposed Flutter's command syntax:

```dart
await _runBuild(root, ['pub', 'get', '--enforce-lockfile']);
final inputs = await captureReleaseInputs(root);
await _runBuild(root, ['build', 'linux', '--release', '--no-pub']);
```

It now names the operations:

```dart
final flutter = _FlutterBuild(root);
await flutter.resolveLockedDependencies();
final inputs = await captureReleaseInputs(root);
await flutter.buildLinuxRelease();
```

`_FlutterBuild` owns the Flutter subprocess boundary, its working directory,
inherited terminal output, and failure handling. Its methods retain the same
arguments and await the child exit status.

The AppImage packager previously decoded a build record at its call site:

```dart
final stamp = await recordReleaseBuild(
  appBundle,
  (built['inputs'] as Map).cast<String, Object>(),
  staticPortableHelper: true,
);
```

It now receives typed inputs:

```dart
final stamp = await recordReleaseBuild(
  appBundle,
  built.inputs,
  staticPortableHelper: true,
);
```

The same change replaces `(built['inputs'] as Map)['commit']` with
`built.inputs.commit`, and nested package casts with
`recordedInputs[entry.key]!.files`. JSON conversion belongs in
[`build_record.dart`](../tool/release_source/build_record.dart) and the manifest
writers. Records without the helper configuration or bundle inventory are
rejected when decoded, before source pairing.

## Keep details where they belong

| File | Responsibility |
| --- | --- |
| `package_release.dart` | CLI arguments, build/archive sequence, exit status |
| `release_source/linux_build.dart` | Flutter commands, notices, built-bundle recording |
| `release_source/build_record.dart` | Typed source/build records and their JSON representation |
| `release_source/source_inputs.dart` | Git state, resolved runtime packages, SDK provenance |
| `release_source/source_archive.dart` | Verify source pairing, stage sources, write manifests, clean up |
| `release_source/source_files.dart` | Copy files, preserve modes/links, inventory checksums, run archive tools |
| `release_source/rebuild_instructions.dart` | Rebuild instructions shipped in the source archive |

Apply this standard to new and revised scripts:

- Use descriptive names for operations, arguments, values, and failures.
- Pass typed records, files, and directories between operations. Decode external
  data at its boundary; keep nested casts out of the workflow.
- Use enums for named choices. Convert them to command or protocol strings at
  the external boundary.
- Extract a real responsibility: a CLI boundary, a repeated contract, or a
  cohesive set of file operations. A short script may need no extra file.
- Keep reusable mechanics in responsibility-named files. Avoid a generic
  `utils` folder, one-method forwarding layers, and a script framework.
- Preserve validation, authorization, timeouts, exit status, cleanup, and the
  order in which inputs are recorded and verified.
- Keep hardware changes behind the existing service/authorization boundary.
  Readability work is not permission to run hardware diagnostics.

## Verification

The focused release, Debian, AppImage, release-workflow, and CI-selection suites
passed 113 tests. The full suite passed 888 tests and skipped 28. Analysis passed.
A separate comparison ran the old packager at
`fae4d59` and this implementation against the same synthetic Git checkout,
dependency files, symlink, executable mode, binary/helper files, and runtime
source input. Records, manifests, and compressed archive bytes matched for both
ordinary and static-helper records. The fixture files were chosen to exercise
source pairing and archive preservation without compiling or running hardware
code; they are not production binaries.

The existing tests still reject changed source inputs, a changed binary or
helper, a non-executable helper, external links, and untracked app source. Added
checks cover serialized build records, the static-helper rebuild recipe, CLI
failure status, destination paths, and CI selection for the moved code.

These fixture checks do not qualify a newly built AppImage or Debian package.
Hosted packaging and acceptance checks remain the release requirement.
