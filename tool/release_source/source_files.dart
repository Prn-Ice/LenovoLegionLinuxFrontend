import 'dart:convert';
import 'dart:io';

import 'build_record.dart';

bool excludedPackageEntry(String name) =>
    const {
      '.git',
      '.beads',
      '.dart_tool',
      'build',
      'coverage',
      '.env',
    }.contains(name) ||
    name.startsWith('.env.');

Future<void> copyPackageSources(Directory from, Directory to) async {
  await to.create(recursive: true);
  await for (final entry in from.list(followLinks: false)) {
    final name = entry.uri.pathSegments.where((part) => part.isNotEmpty).last;
    if (excludedPackageEntry(name)) continue;
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

Future<ReleaseTreeInventory> inventoryReleaseTree(
  Directory root, {
  bool packageSource = false,
}) async {
  final entries = <String, Map<String, String>>{};
  final files = <String, File>{};
  Future<void> visit(FileSystemEntity entity, String relative) async {
    final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      final target = await Link(entity.path).target();
      final resolved = File.fromUri(entity.parent.absolute.uri.resolve(target))
          .path;
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
        final name = child.uri.pathSegments
            .where((part) => part.isNotEmpty)
            .last;
        if (packageSource && relative == '.' && excludedPackageEntry(name)) {
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
    entries.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key)),
  );
}

Future<String> releaseFileSha256(File file) async {
  final result = await Process.run('sha256sum', [
    '--binary',
    '--zero',
    '--',
    file.path,
  ]);
  if (result.exitCode != 0) throw StateError(result.stderr.toString());
  return (result.stdout as String).substring(0, 64);
}

Future<void> extractApplicationSource(
  Directory root,
  Directory destination,
  String commit,
) async {
  await destination.create();
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

Future<void> createSourceArchive(Directory staging, File output) async {
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
}
