import 'dart:convert';
import 'dart:io';

import '../nix_flutter_provenance.dart';
import 'build_record.dart';
import 'source_files.dart';

typedef PackageSource = ({Directory root, String version});
typedef ResolvedReleaseSources = ({
  Map<String, PackageSource> packages,
  Directory? sdk,
});

Future<ReleaseInputs> captureReleaseInputs(Directory root) async {
  requireCleanSourceTree(root);
  final sources = await resolveReleaseSources(root);
  return ReleaseInputs(
    commit: _runGit(root, ['rev-parse', 'HEAD']).trim(),
    lockfileSha256: await releaseFileSha256(File('${root.path}/pubspec.lock')),
    packages: {
      for (final entry in sources.packages.entries)
        entry.key: ReleasePackageInputs(
          version: entry.value.version,
          files: await inventoryReleaseTree(
            entry.value.root,
            packageSource: true,
          ),
        ),
    },
    flutterSdk: sources.sdk == null
        ? null
        : await _flutterMetadata(sources.sdk!),
  );
}

Future<ResolvedReleaseSources> resolveReleaseSources(Directory root) async {
  final configFile = File('${root.path}/.dart_tool/package_config.json');
  final config = jsonDecode(await configFile.readAsString()) as Map;
  final graph = jsonDecode(
    await File('${root.path}/.dart_tool/package_graph.json').readAsString(),
  ) as Map;
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
  final packages = <String, PackageSource>{};
  for (final name in names) {
    // The application's own source comes from git archive.
    if (roots.contains(name)) continue;
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

void requireCleanSourceTree(Directory root) {
  if (_runGit(root, ['status', '--porcelain']).trim().isNotEmpty) {
    throw StateError('Release packaging needs a clean worktree.');
  }
}

String _runGit(Directory root, List<String> arguments) {
  final result = Process.runSync('git', arguments, workingDirectory: root.path);
  if (result.exitCode != 0) throw StateError(result.stderr.toString());
  return result.stdout as String;
}

Future<Map<String, Object>> _flutterMetadata(Directory sdk) async {
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
    'source_provenance': await nixFlutterProvenance(sdk),
  };
}
