// Build the Linux app and archive the sources used by that build.
import 'dart:convert';
import 'dart:io';

import 'bundle_notices.dart' show bundleNotices;

Future<void> main(List<String> args) async {
  try {
    final output = switch (args) {
      [] => 'build/release/legion-frontend-source.tar.gz',
      ['--output', final String path] when !path.startsWith('--') => path,
      _ => throw const FormatException(
        'Usage: dart tool/package_release.dart [--output archive.tar.gz]',
      ),
    };
    final root = File.fromUri(Platform.script).parent.parent;
    _requireCleanTree(root);
    await _runBuild(root, ['pub', 'get', '--enforce-lockfile']);
    final inputs = await captureReleaseInputs(root);
    await _runBuild(root, ['build', 'linux', '--release', '--no-pub']);
    final bundle = Directory('${root.path}/build/linux/x64/release/bundle');
    await bundleNotices(root, bundle);
    final stamp = <String, Object>{
      'inputs': inputs,
      'binary_sha256': await _sha256(File('${bundle.path}/lib/libapp.so')),
    };
    final archive = File.fromUri(root.uri.resolve(output));
    await packageReleaseSource(root, bundle, archive, stamp);
    stdout.writeln('Packaged release source: ${archive.path}');
  } catch (error) {
    stderr.writeln('Release source: $error');
    exitCode = error is FormatException ? 64 : 1;
  }
}

/// Record source contents before building, so later edits cannot silently become
/// the source archive for an earlier binary.
Future<Map<String, Object>> captureReleaseInputs(Directory root) async {
  _requireCleanTree(root);
  final sources = await _resolveSources(root);
  return {
    'commit': _run(root, 'git', ['rev-parse', 'HEAD']).stdout.toString().trim(),
    'lockfile_sha256': await _sha256(File('${root.path}/pubspec.lock')),
    'packages': {
      for (final entry in sources.packages.entries)
        entry.key: {
          'version': entry.value.version,
          'files': await _inventory(entry.value.root, packageSource: true),
        },
    },
    'flutter_sdk': sources.sdk == null
        ? 'not resolved'
        : await _flutterMetadata(sources.sdk!),
  };
}

/// Pair a built bundle with the recorded inputs. The CLI always builds first;
/// this function also lets tests use small source and binary fixtures.
Future<Map<String, Object>> packageReleaseSource(
  Directory root,
  Directory bundle,
  File output,
  Map<String, Object> stamp,
) async {
  final inputs = stamp['inputs'] as Map;
  if (jsonEncode(await captureReleaseInputs(root)) != jsonEncode(inputs)) {
    throw StateError('Sources changed during the build; build again.');
  }
  if (await _sha256(File('${bundle.path}/lib/libapp.so')) !=
      stamp['binary_sha256']) {
    throw StateError('The built libapp.so changed; build again.');
  }
  final sources = await _resolveSources(root);
  final staging = await Directory.systemTemp.createTemp('legion-release-');
  try {
    final source = Directory('${staging.path}/source');
    await source.create();
    await _gitArchive(root, source, inputs['commit'] as String);
    for (final entry in sources.packages.entries) {
      final copied = Directory('${staging.path}/dependencies/${entry.key}');
      await _copyPackage(entry.value.root, copied);
      final expected = (inputs['packages'] as Map)[entry.key]['files'];
      if (jsonEncode(await _inventory(copied)) != jsonEncode(expected)) {
        throw StateError('${entry.key} changed while copying; build again.');
      }
    }
    // Paths are relative to source/pubspec_overrides.yaml after the user copies
    // this file there. This makes a rebuild use any archived package edits.
    await File('${staging.path}/dependency-overrides.yaml').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({
        'dependency_overrides': {
          for (final name in sources.packages.keys) name: {'path': '../dependencies/$name'},
        },
      })}\n',
    );
    await File('${staging.path}/REBUILD.md').writeAsString(
      '''# Rebuild this release

Use the SDK-reported Flutter version and framework/engine revisions in
SOURCE-MANIFEST.json. Distributor SDKs can report a placeholder framework
revision; obtain that SDK's source from its distributor in that case.
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
''',
    );
    final manifest = <String, Object>{
      'format': 3,
      'inputs': inputs,
      'binary_sha256': stamp['binary_sha256']!,
      'bundle': await _inventory(bundle),
      'application_source': await _inventory(source),
    };
    await File('${staging.path}/SOURCE-MANIFEST.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
    );
    await output.parent.create(recursive: true);
    final result = await Process.run('tar', [
      '--sort=name',
      '--mtime=@0',
      '--owner=0',
      '--group=0',
      '--numeric-owner',
      '-czf',
      output.absolute.path,
      '-C',
      staging.path,
      '.',
    ]);
    if (result.exitCode != 0) throw StateError(result.stderr.toString());
    return manifest;
  } finally {
    // Copied source directories can be read-only; the archive already retains
    // their modes. Make this owned temporary copy removable.
    await Process.run('chmod', ['-R', 'u+w', '--', staging.path]);
    await staging.delete(recursive: true);
  }
}

typedef _PackageSource = ({Directory root, String version});

Future<({Map<String, _PackageSource> packages, Directory? sdk})>
_resolveSources(Directory root) async {
  final configFile = File('${root.path}/.dart_tool/package_config.json');
  final config = jsonDecode(await configFile.readAsString()) as Map;
  final graph =
      jsonDecode(
            await File(
              '${root.path}/.dart_tool/package_graph.json',
            ).readAsString(),
          )
          as Map;
  final nodes = <String, Map>{
    for (final item in graph['packages'] as List)
      (item as Map)['name'] as String: item,
  };
  final directories = <String, Directory>{};
  for (final item in config['packages'] as List) {
    final uri = configFile.absolute.uri.resolve(item['rootUri'] as String);
    if (uri.scheme != 'file') throw StateError('Package source is not local.');
    directories[item['name'] as String] = Directory(
      Directory.fromUri(uri).absolute.path.replaceFirst(RegExp(r'/+$'), ''),
    );
  }
  final sdk = directories['flutter']?.parent.parent;
  final runtime = <String>{};
  void visit(String name) {
    if (!runtime.add(name)) return;
    for (final dependency in nodes[name]!['dependencies'] as List) {
      visit(dependency as String);
    }
  }

  final roots = (graph['roots'] as List).cast<String>();
  for (final root in roots) {
    visit(root);
  }
  final names = runtime.toList()..sort();
  final packages = <String, _PackageSource>{};
  for (final name in names) {
    if (roots.contains(name)) {
      continue; // App source comes only from git archive.
    }
    final directory = directories[name];
    if (directory == null) throw StateError('No resolved source for $name.');
    if (sdk != null && directory.path.startsWith('${sdk.path}/')) continue;
    packages[name] = (
      root: directory,
      version: nodes[name]!['version'] as String,
    );
  }
  return (packages: packages, sdk: sdk);
}

bool _excludedPackageEntry(String name) =>
    const {
      '.git',
      '.beads',
      '.dart_tool',
      'build',
      'coverage',
      '.env',
    }.contains(name) ||
    name.startsWith('.env.');

Future<void> _copyPackage(Directory from, Directory to) async {
  await to.create(recursive: true);
  await for (final entry in from.list(followLinks: false)) {
    final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (_excludedPackageEntry(name)) continue;
    final result = await Process.run('cp', [
      '-a',
      '--',
      entry.path,
      '${to.path}/$name',
    ]);
    if (result.exitCode != 0) throw StateError(result.stderr.toString());
  }
  final mode = (FileStat.statSync(from.path).mode & 0x1ff).toRadixString(8);
  final result = await Process.run('chmod', [mode, to.path]);
  if (result.exitCode != 0) throw StateError(result.stderr.toString());
}

Future<Map<String, Map<String, String>>> _inventory(
  Directory root, {
  bool packageSource = false,
}) async {
  final entries = <String, Map<String, String>>{};
  final files = <String, File>{};
  Future<void> visit(FileSystemEntity entity, String relative) async {
    final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      final target = await Link(entity.path).target();
      final resolved = File.fromUri(
        entity.parent.absolute.uri.resolve(target),
      ).path;
      if (target.startsWith('/') ||
          !resolved.startsWith('${root.absolute.path}/')) {
        throw StateError('External source link: $relative');
      }
      entries[relative] = {'type': 'link', 'target': target};
      return;
    }
    final mode = (FileStat.statSync(entity.path).mode & 0x1ff).toRadixString(8);
    if (type == FileSystemEntityType.file) {
      entries[relative] = {'type': 'file', 'mode': mode};
      files[relative] = File(entity.path);
    } else if (type == FileSystemEntityType.directory) {
      entries[relative] = {'type': 'directory', 'mode': mode};
      await for (final child in Directory(
        entity.path,
      ).list(followLinks: false)) {
        final name = child.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (packageSource && relative == '.' && _excludedPackageEntry(name)) {
          continue;
        }
        await visit(child, '$relative/$name');
      }
    } else {
      throw StateError('Unsupported source file type: $relative');
    }
  }

  await visit(root, '.');
  final fileList = files.entries.toList();
  for (var start = 0; start < fileList.length; start += 128) {
    final batch = fileList.skip(start).take(128).toList();
    final result = await Process.run('sha256sum', [
      '--binary',
      '--zero',
      '--',
      ...batch.map((entry) => entry.value.path),
    ]);
    if (result.exitCode != 0) throw StateError(result.stderr.toString());
    final hashes = <String, String>{
      for (final record in (result.stdout as String).split('\u0000'))
        if (record.isNotEmpty) record.substring(66): record.substring(0, 64),
    };
    for (final entry in batch) {
      final hash = hashes[entry.value.path];
      if (hash == null) throw StateError('Missing checksum for ${entry.key}');
      entries[entry.key]!['sha256'] = hash;
    }
  }
  return Map.fromEntries(
    entries.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

Future<void> _gitArchive(
  Directory root,
  Directory destination,
  String commit,
) async {
  final git = await Process.start('git', [
    'archive',
    '--format=tar',
    commit,
  ], workingDirectory: root.path);
  final tar = await Process.start('tar', ['-xf', '-', '-C', destination.path]);
  final gitError = git.stderr.transform(utf8.decoder).join();
  final tarError = tar.stderr.transform(utf8.decoder).join();
  await git.stdout.pipe(tar.stdin);
  final codes = await Future.wait([git.exitCode, tar.exitCode]);
  if (codes.any((code) => code != 0)) {
    throw StateError(
      'Could not extract source: ${await gitError}${await tarError}',
    );
  }
  await gitError;
  await tarError;
}

void _requireCleanTree(Directory root) {
  final status = _run(root, 'git', ['status', '--porcelain']).stdout as String;
  if (status.trim().isNotEmpty) {
    throw StateError('Release packaging needs a clean worktree.');
  }
}

ProcessResult _run(Directory root, String executable, List<String> args) {
  final result = Process.runSync(executable, args, workingDirectory: root.path);
  if (result.exitCode != 0) throw StateError(result.stderr.toString());
  return result;
}

Future<void> _runBuild(Directory root, List<String> args) async {
  final process = await Process.start(
    'flutter',
    args,
    workingDirectory: root.path,
    mode: ProcessStartMode.inheritStdio,
  );
  if (await process.exitCode != 0) {
    throw StateError('Flutter ${args.first} failed.');
  }
}

Future<String> _sha256(File file) async {
  final result = await Process.run('sha256sum', [
    '--binary',
    '--zero',
    '--',
    file.path,
  ]);
  if (result.exitCode != 0) throw StateError(result.stderr.toString());
  return (result.stdout as String).substring(0, 64);
}

Future<Map<String, String>> _flutterMetadata(Directory sdk) async {
  final result = await Process.run('${sdk.path}/bin/flutter', [
    '--version',
    '--machine',
  ]);
  if (result.exitCode != 0) {
    throw StateError('Flutter SDK metadata unavailable.');
  }
  final metadata = jsonDecode(result.stdout as String) as Map;
  return {
    for (final key in [
      'frameworkVersion',
      'frameworkRevision',
      'engineRevision',
      'dartSdkVersion',
    ])
      key: switch (metadata[key]) {
        final String value when value.isNotEmpty => value,
        _ => throw StateError('Flutter metadata lacks $key.'),
      },
  };
}
