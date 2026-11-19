// Validate tag builds and publish GitHub releases from checked artifacts.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'git_environment.dart';
import 'packaging_files.dart';
import 'packaging_versions.dart';
import 'package_test_results.dart'
    show passedAppImageChecks, passedDebianChecks;

export 'package_test_results.dart'
    show passedAppImageChecks, passedDebianChecks;

enum ReleaseCommand { checkTag, prepare, publish }

enum ReleaseSection {
  breaking('Breaking changes'),
  features('Features'),
  fixes('Fixes'),
  improvements('Improvements'),
  documentation('Documentation'),
  maintenance('Maintenance');

  const ReleaseSection(this.heading);
  final String heading;
}

const releaseHelperPath =
    'usr/lib/legion_frontend/libexec/legion-portable-control';
const debianChecks = {
  'installation',
  'desktop',
  'helper',
  'denied',
  'missing_agent',
  'upgrade',
  'purge',
  'existing_integration_preserved',
};

List<String> debianNames(Map release) {
  final version = release['version'] as String;
  final prefix = 'legion-frontend-$version-amd64';
  return [
    debianFileName(version),
    '$prefix-source.tar.gz',
    '$prefix.json',
    '$prefix-acceptance.tar.gz',
  ];
}

File releaseFile(File file) {
  if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
          FileSystemEntityType.file ||
      file.lengthSync() == 0) {
    throw StateError(
      'Required release file is missing, empty, or a symlink: ${fileName(file)}',
    );
  }
  return file;
}

String releaseSha256(File file) => packagingSha256(releaseFile(file));
Map readReleaseJson(File file) =>
    jsonDecode(releaseFile(file).readAsStringSync()) as Map;

bool sameNames(Iterable names, Iterable expected) =>
    sameJson(names.toList()..sort(), expected.toList()..sort());

Map<String, String> releaseChecksums(
  Directory directory,
  Set<String> expected,
) {
  final checksums = <String, String>{};
  for (final line in releaseFile(
    File('${directory.path}/SHA256SUMS'),
  ).readAsLinesSync()) {
    final match = RegExp(r'^([0-9a-f]{64})  ([^\r\n]+)$').firstMatch(line);
    if (match == null ||
        !expected.contains(match[2]) ||
        checksums.containsKey(match[2])) {
      throw StateError(
        'The release checksum file contains an unexpected or duplicate entry.',
      );
    }
    checksums[match[2]!] = match[1]!;
  }
  if (!sameNames(checksums.keys, expected)) {
    throw StateError('The release checksum file is incomplete.');
  }
  for (final entry in checksums.entries) {
    if (releaseSha256(File('${directory.path}/${entry.key}')) != entry.value) {
      throw StateError('Release checksum differs: ${entry.key}');
    }
  }
  return checksums;
}

String archivedText(File archive, String name) {
  releaseFile(archive);
  // Inspect the member without extracting paths or following archived links.
  final members = packagingCommand('tar', [
    '--list',
    '--verbose',
    '--quoting-style=literal',
    '--file',
    archive.absolute.path,
    '--',
    name,
  ]).trimRight().split('\n');
  if (members.length != 1 || !members.single.startsWith('-')) {
    throw StateError('Expected a regular archived manifest: $name');
  }
  return packagingCommand('tar', ['-xOf', archive.absolute.path, '--', name]);
}

Map archivedJson(File archive, String name) =>
    jsonDecode(archivedText(archive, name)) as Map;

void verifyHelperFile(File helper, Map expected, String packageName) {
  releaseFile(helper);
  final mode = helper.statSync().mode & 0x1ff;
  if ((mode & 0x49) == 0 ||
      mode.toRadixString(8) != expected['mode'] ||
      releaseSha256(helper) != expected['sha256']) {
    throw StateError('$packageName helper payload differs from its inventory.');
  }
}

void verifyDebianHelper(File package, Map expected) {
  final staging = Directory.systemTemp.createTempSync('release-debian-helper-');
  try {
    final archive = File('${staging.path}/payload.tar')
      ..writeAsBytesSync(
        packagingCommandBytes('dpkg-deb', [
          '--fsys-tarfile',
          package.absolute.path,
        ]),
      );
    final members = const LineSplitter()
        .convert(packagingCommand('tar', ['--list', '--file', archive.path]))
        .where(
          (name) => name.replaceFirst(RegExp(r'^\./'), '') == releaseHelperPath,
        )
        .toList();
    if (members.length != 1) {
      throw StateError(
        'The Debian payload lacks a regular privileged control helper.',
      );
    }
    final listing = const LineSplitter().convert(
      packagingCommand('tar', [
        '--list',
        '--verbose',
        '--quoting-style=literal',
        '--file',
        archive.path,
        '--',
        members.single,
      ]),
    );
    final mode = int.tryParse(expected['mode'].toString(), radix: 8);
    if (listing.length != 1 ||
        !listing.single.startsWith('-') ||
        mode == null ||
        mode < 0 ||
        mode > 0x1ff ||
        (mode & 0x49) == 0) {
      throw StateError(
        'The Debian payload lacks a regular executable privileged control helper.',
      );
    }
    const permissionLetters = 'rwxrwxrwx';
    final permissions = StringBuffer('-');
    for (var index = 0; index < permissionLetters.length; index++) {
      final bit = 1 << (8 - index);
      permissions.write((mode & bit) == 0 ? '-' : permissionLetters[index]);
    }
    if (!listing.single.startsWith('$permissions ')) {
      throw StateError('The Debian helper payload differs from its inventory.');
    }
    // Read only the selected member; never extract package paths or links.
    final helper = File('${staging.path}/helper')
      ..writeAsBytesSync(
        packagingCommandBytes('tar', [
          '-xOf',
          archive.path,
          '--',
          members.single,
        ]),
      );
    releaseFile(helper);
    if (releaseSha256(helper) != expected['sha256']) {
      throw StateError('The Debian helper payload differs from its inventory.');
    }
  } finally {
    staging.deleteSync(recursive: true);
  }
}

void verifyAppImageHelper(File image, Object? runtimeSize, Map expected) {
  if (runtimeSize is! int ||
      runtimeSize <= 0 ||
      runtimeSize >= image.lengthSync()) {
    throw StateError('The AppImage runtime size is invalid.');
  }
  final staging = Directory.systemTemp.createTempSync(
    'release-appimage-helper-',
  );
  try {
    final destination = Directory('${staging.path}/payload');
    packagingCommand('unsquashfs', [
      '-no-progress',
      '-no-xattrs',
      '-o',
      '$runtimeSize',
      '-d',
      destination.path,
      image.absolute.path,
      releaseHelperPath,
    ]);
    verifyHelperFile(
      File('${destination.path}/$releaseHelperPath'),
      expected,
      'The AppImage',
    );
  } finally {
    staging.deleteSync(recursive: true);
  }
}

void archiveEvidence(File output, Map<String, File> files) {
  final staging = Directory.systemTemp.createTempSync('release-evidence-');
  try {
    for (final entry in files.entries) {
      final target = File('${staging.path}/${entry.key}');
      target.parent.createSync(recursive: true);
      releaseFile(entry.value).copySync(target.path);
    }
    packagingCommand('tar', [
      '-czf',
      output.absolute.path,
      '-C',
      staging.path,
      '--',
      ...files.keys,
    ]);
  } finally {
    staging.deleteSync(recursive: true);
  }
}

String releaseGit(Directory root, List<String> arguments) => packagingCommand(
  'git',
  ['-C', root.path, ...arguments],
  environment: gitRepositoryEnvironment(),
).trim();

String releaseNotes(Directory root, String tag) {
  if (releaseGit(root, ['rev-parse', '--is-shallow-repository']) == 'true') {
    throw StateError(
      'Fetch the full Git history before generating release notes.',
    );
  }
  final commit = releaseGit(root, ['rev-parse', 'refs/tags/$tag^{commit}']);
  final versionTag = RegExp(r'^v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$');
  final previousTags = releaseGit(root, ['tag', '--merged', commit])
      .split('\n')
      .where((name) => name != tag && versionTag.hasMatch(name))
      .toList();
  final previous = previousTags.isEmpty
      ? null
      : releaseGit(root, [
          'describe',
          '--tags',
          '--abbrev=0',
          for (final name in previousTags) '--match=$name',
          commit,
        ]);
  final history = releaseGit(root, [
    'log',
    '--reverse',
    '--topo-order',
    '--no-merges',
    '-z',
    '--format=%h%n%B',
    previous == null ? commit : '$previous..$commit',
    '--',
  ]);
  final sections = <ReleaseSection, List<String>>{};
  final conventional = RegExp(r'^([a-z]+)(?:\(([^()]+)\))?(!)?: (.+)$');
  const repository = 'https://github.com/Prn-Ice/LenovoLegionLinuxFrontend';
  for (final entry
      in history.split('\x00').where((entry) => entry.isNotEmpty)) {
    final lines = const LineSplitter().convert(entry.trim());
    final hash = lines.first;
    final subject = lines[1];
    final match = conventional.firstMatch(subject);
    final breaking =
        match?[3] != null ||
        lines
            .skip(2)
            .any((line) => RegExp(r'^BREAKING[ -]CHANGE: \S').hasMatch(line));
    final section = breaking
        ? ReleaseSection.breaking
        : switch (match?[1]) {
            'feat' => ReleaseSection.features,
            'fix' || 'revert' => ReleaseSection.fixes,
            'perf' || 'refactor' => ReleaseSection.improvements,
            'docs' => ReleaseSection.documentation,
            _ => ReleaseSection.maintenance,
          };
    final description = match?[4] ?? subject;
    final scope = match?[2];
    sections
        .putIfAbsent(section, () => [])
        .add(
          '- ${scope == null ? '' : '$scope: '}$description '
          '([$hash]($repository/commit/$hash))',
        );
  }
  final notes = StringBuffer('## What changed\n');
  if (sections.isEmpty) notes.writeln('\nNo new commits.');
  for (final section in ReleaseSection.values) {
    final entries = sections[section];
    if (entries == null) continue;
    notes
      ..writeln('\n### ${section.heading}\n')
      ..writeln(entries.join('\n'));
  }
  final changelog = previous == null
      ? '$repository/commits/$tag'
      : '$repository/compare/$previous...$tag';
  notes.writeln('\n[Full changelog]($changelog)');
  return notes.toString();
}

Map<String, Object> checkTag(Directory root, String tag) {
  final match = RegExp(
    r'^version:[ \t]*([^\s]+)[ \t]*$',
    multiLine: true,
  ).firstMatch(File('${root.path}/pubspec.yaml').readAsStringSync());
  if (match == null ||
      !RegExp(r'^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$')
          .hasMatch(match[1]!)) {
    throw StateError('pubspec.yaml needs an unquoted release version.');
  }
  final version = match[1]!;
  final expectedTag = 'v${version.split('+').first}';
  if (tag != expectedTag) {
    throw StateError(
      'Expected tag $expectedTag for pubspec version $version; received $tag.',
    );
  }
  final commit = releaseGit(root, ['rev-parse', 'HEAD']);
  final tagged = releaseGit(root, [
    'rev-parse',
    '--verify',
    'refs/tags/$tag^{commit}',
  ]);
  if (commit != tagged) {
    throw StateError('The checked-out commit differs from the release tag.');
  }
  return {
    'tag': tag,
    'commit': commit,
    'version': version,
    'prerelease': expectedTag.contains('-'),
  };
}

void validateAppImageRuntime(Map manifest, Map sources, Map archived) {
  final native = manifest['native_runtime'] as Map;
  if (!sameJson(native, archived) ||
      native['format'] != 1 ||
      native['helper']['linkage'] != 'static') {
    throw StateError(
      'The native runtime source manifest differs from the AppImage.',
    );
  }
  if (sources['build_config']['static_portable_helper'] != true) {
    throw StateError(
      'The source companion lacks the static helper build configuration.',
    );
  }
  final cleanup = native['helper']['cleanup'] as Map? ?? {};
  final size = cleanup['size'] as num? ?? 0;
  if (size <= 0 ||
      size >= 64 * 1024 ||
      sources['release_inputs']['./native/portable-cleanup.elf']?['sha256'] !=
          cleanup['sha256']) {
    throw StateError('The source companion lacks the bounded cleanup ELF.');
  }
  final files = native['files'] as Map;
  if (!files.containsKey('usr/lib/legion_frontend/lib/libgtk-3.so.0')) {
    throw StateError('The AppImage runtime lacks bundled GTK.');
  }
  for (final entry in files.entries) {
    if (manifest['appdir']['./${entry.key}']?['sha256'] !=
        entry.value['sha256']) {
      throw StateError(
        'The native runtime differs from a shipped file: ${entry.key}',
      );
    }
    if (!(native['packages'] as Map).containsKey(entry.value['package'])) {
      throw StateError('Missing source package attribution for ${entry.key}');
    }
  }
  for (final entry in (native['packages'] as Map).entries) {
    if (native['sources'][entry.value['source']]?['version'] !=
        entry.value['source_version']) {
      throw StateError('Missing exact source version for ${entry.key}');
    }
  }
  for (final entry in (native['sources'] as Map).entries) {
    for (final archive in (entry.value['archives'] as Map).entries) {
      final path = './native/sources/${entry.key}/${archive.key}';
      if (sources['release_inputs'][path]?['sha256'] != archive.value) {
        throw StateError(
          'The source companion lacks an exact native archive: $path',
        );
      }
    }
  }
}

List<String> prepareDebian(Map release, Directory inputs, Directory output) {
  final names = debianNames(release);
  final package = names[0], source = names[1], metadata = names[2];
  final directory = Directory('${inputs.path}/deb-release');
  final checksums = releaseChecksums(directory, {package, source, metadata});
  final manifest = readReleaseJson(File('${directory.path}/$metadata'));
  if (manifest['format'] != 1 ||
      manifest['architecture'] != 'amd64' ||
      manifest['version'] != release['version'] ||
      manifest['package_version'] !=
          debianVersion(release['version'] as String) ||
      manifest['source_commit'] != release['commit'] ||
      manifest['portable_control'] != true ||
      manifest['default_control_mode'] != 'privilegedControlHelper' ||
      !sameJson(manifest['files'], {
        for (final name in [package, source]) name: checksums[name],
      })) {
    throw StateError(
      'The Debian build differs from the tagged portable release.',
    );
  }
  final sources = archivedJson(
    File('${directory.path}/$source'),
    './SOURCE-MANIFEST.json',
  );
  if (sources['format'] != 4 ||
      sources['inputs']['commit'] != release['commit'] ||
      sources['build_config']['portable_control'] != true ||
      !sameJson(sources['bundle'], manifest['bundle'])) {
    throw StateError(
      'The Debian source companion differs from its shipped bundle.',
    );
  }
  for (final name in [
    './legion_frontend',
    './lib/libapp.so',
    './libexec/legion-portable-control',
  ]) {
    if (manifest['bundle'][name]?['type'] != 'file') {
      throw StateError('The Debian bundle lacks $name.');
    }
  }
  verifyDebianHelper(
    File('${directory.path}/$package'),
    manifest['bundle']['./libexec/legion-portable-control'] as Map,
  );
  for (final distribution in {
    'ubuntu': ['ID=ubuntu', 'VERSION_ID="22.04"'],
    'debian': ['ID=debian', 'VERSION_ID="12"'],
  }.entries) {
    final label = distribution.key;
    final qaDirectory = Directory('${inputs.path}/deb-$label-qualification');
    final qa = readReleaseJson(File('${qaDirectory.path}/manifest.json'));
    if (qa['commit'] != release['commit'] ||
        qa['source_worktree_modified'] != false ||
        qa['deb'] != passedDebianChecks) {
      throw StateError('Debian package acceptance is incomplete for $label.');
    }
    const expected = {'native-source.tar.gz', 'deb-qualification.tar.gz'};
    if (!sameNames((qa['files'] as Map).keys, expected)) {
      throw StateError('The Debian VM evidence list is incomplete.');
    }
    for (final name in expected) {
      if (releaseSha256(File('${qaDirectory.path}/$name')) !=
          qa['files'][name]) {
        throw StateError('Debian VM evidence checksum differs: $name');
      }
    }
    final archive = File('${qaDirectory.path}/deb-qualification.tar.gz');
    if (!sameJson(
      archivedJson(archive, 'deb-release-manifest.json'),
      manifest,
    )) {
      throw StateError('The VM tested a different Debian package.');
    }
    final checks = archivedJson(archive, 'deb-checks.json');
    if (!sameNames(checks.keys, debianChecks) ||
        checks.values.any((value) => value != true)) {
      throw StateError('A required Debian acceptance check has not passed.');
    }
    final osRelease = const LineSplitter().convert(
      archivedText(archive, 'deb-os-release'),
    );
    if (!distribution.value.every(osRelease.contains)) {
      throw StateError(
        'The Debian package evidence identifies the wrong distribution.',
      );
    }
  }
  for (final name in names.take(3)) {
    File('${directory.path}/$name').copySync('${output.path}/$name');
  }
  archiveEvidence(File('${output.path}/${names[3]}'), {
    for (final label in ['ubuntu', 'debian'])
      for (final name in [
        'manifest.json',
        'native-source.tar.gz',
        'deb-qualification.tar.gz',
        'qualification.log',
      ])
        '$label/$name': File('${inputs.path}/deb-$label-qualification/$name'),
  });
  return names;
}

Map<String, Object> prepareRelease(
  Directory root,
  String tag,
  Directory inputs,
  Directory output,
) {
  final release = checkTag(root, tag);
  final prefix = 'legion-frontend-${release['version']}-x86_64';
  final directory = Directory('${inputs.path}/appimage-release');
  final qaDirectory = Directory('${inputs.path}/appimage-qualification');
  final image = '$prefix.AppImage', source = '$prefix-source.tar.gz';
  final metadata = '$prefix.json';
  final checksums = releaseChecksums(directory, {image, source, metadata});
  final manifest = readReleaseJson(File('${directory.path}/$metadata'));
  if (manifest['format'] != 1 ||
      manifest['architecture'] != 'x86_64' ||
      manifest['portable_control'] != true ||
      manifest['default_control_mode'] != 'privilegedControlHelper') {
    throw StateError('Expected a portable Ubuntu x86-64 AppImage manifest.');
  }
  if (manifest['version'] != release['version'] ||
      manifest['source_commit'] != release['commit']) {
    throw StateError(
      'The AppImage version or source commit differs from the tag.',
    );
  }
  if (!sameJson(manifest['files'], {
    image: checksums[image],
    source: checksums[source],
  })) {
    throw StateError('The AppImage manifest and checksums differ.');
  }
  final sources = archivedJson(
    File('${directory.path}/$source'),
    './SOURCE-MANIFEST.json',
  );
  if (sources['format'] != 4 ||
      sources['inputs']['commit'] != release['commit'] ||
      sources['build_config']['portable_control'] != true) {
    throw StateError(
      'The source companion does not describe this portable build.',
    );
  }
  const bundlePrefix = './usr/lib/legion_frontend';
  final shipped = <String, Object?>{
    for (final entry in (manifest['appdir'] as Map).entries)
      if (entry.key == bundlePrefix ||
          (entry.key as String).startsWith('$bundlePrefix/'))
        '.${(entry.key as String).substring(bundlePrefix.length)}': entry.value,
  };
  if (!sameJson(sources['bundle'], shipped)) {
    throw StateError(
      'The source manifest differs from the complete shipped bundle.',
    );
  }
  for (final path in [
    './legion_frontend',
    './lib/libapp.so',
    './libexec/legion-portable-control',
  ]) {
    if ((shipped[path] as Map?)?['type'] != 'file') {
      throw StateError('The shipped bundle lacks $path.');
    }
  }
  verifyAppImageHelper(
    File('${directory.path}/$image'),
    manifest['runtime_size'],
    shipped['./libexec/legion-portable-control'] as Map,
  );
  if (sources['build_config']['static_portable_helper'] == true &&
      !manifest.containsKey('native_runtime')) {
    throw StateError(
      'The static AppImage lacks its native runtime source metadata.',
    );
  }
  if (manifest.containsKey('native_runtime')) {
    validateAppImageRuntime(
      manifest,
      sources,
      archivedJson(
        File('${directory.path}/$source'),
        './release-inputs/native/native-runtime.json',
      ),
    );
  }
  final qa = readReleaseJson(File('${qaDirectory.path}/manifest.json'));
  if (qa['commit'] != release['commit'] ||
      qa['source_worktree_modified'] != false) {
    throw StateError(
      'VM qualification used a different or modified source checkout.',
    );
  }
  if (qa['appimage'] != passedAppImageChecks) {
    throw StateError('AppImage VM acceptance has not passed.');
  }
  final qaFiles = {
    'native-source.tar.gz',
    'appimage-qualification.tar.gz',
    if (manifest.containsKey('native_runtime'))
      'appimage-nixos-qualification.tar.gz',
  };
  if (!sameNames((qa['files'] as Map).keys, qaFiles)) {
    throw StateError('The VM evidence file list is incomplete.');
  }
  for (final name in qaFiles) {
    if (releaseSha256(File('${qaDirectory.path}/$name')) != qa['files'][name]) {
      throw StateError('VM evidence checksum differs: $name');
    }
  }
  if (!sameJson(
    archivedJson(
      File('${qaDirectory.path}/appimage-qualification.tar.gz'),
      'appimage-release-manifest.json',
    ),
    manifest,
  )) {
    throw StateError('The VM tested different release artifacts.');
  }
  if (manifest.containsKey('native_runtime')) {
    final nixos = archivedJson(
      File('${qaDirectory.path}/appimage-nixos-qualification.tar.gz'),
      'manifest.json',
    );
    if (nixos['commit'] != release['commit'] ||
        nixos['appimage_sha256'] != checksums[image] ||
        nixos['nixos'] !=
            'official appimage-run desktop and privileged control verified' ||
        nixos['desktop_shutdown'] !=
            'X11 close button and Wayland window close verified') {
      throw StateError('NixOS acceptance did not verify this AppImage.');
    }
  }
  if (output.existsSync()) throw StateError('Release output already exists.');
  output.createSync(recursive: true);
  final assets = [image, source, metadata, '$prefix-acceptance.tar.gz'];
  for (final name in assets.take(3)) {
    File('${directory.path}/$name').copySync('${output.path}/$name');
  }
  archiveEvidence(File('${output.path}/${assets[3]}'), {
    for (final name in [
      'manifest.json',
      'qualification.log',
      ...(qaFiles.toList()..sort()),
    ])
      name: File('${qaDirectory.path}/$name'),
  });
  assets.addAll(prepareDebian(release, inputs, output));
  File('${output.path}/SHA256SUMS').writeAsStringSync(
    assets
        .map(
          (name) => '${releaseSha256(File('${output.path}/$name'))}  $name\n',
        )
        .join(),
  );
  assets.add('SHA256SUMS');
  final notes = File('${output.path}/RELEASE-NOTES.md');
  notes.writeAsStringSync(releaseNotes(root, tag));
  final plan = <String, Object>{
    ...release,
    'assets': {
      for (final name in assets)
        name: releaseSha256(File('${output.path}/$name')),
    },
    'notes_sha256': releaseSha256(notes),
  };
  writePackagingJson(File('${output.path}/release-plan.json'), plan);
  return plan;
}

typedef GitHubApi = Future<Object?> Function(String path);
typedef GitHubCommand = Future<void> Function(List<String> arguments);

Future<ProcessResult> runGitHub(
  List<String> arguments,
  Duration timeout,
) async {
  final process = await Process.start('gh', arguments);
  try {
    final results = await Future.wait<Object>([
      process.stdout.transform(utf8.decoder).join(),
      process.stderr.transform(utf8.decoder).join(),
      process.exitCode,
    ]).timeout(timeout);
    return ProcessResult(
      process.pid,
      results[2] as int,
      results[0],
      results[1],
    );
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
    rethrow;
  }
}

Object? parseGitHubResponse(ProcessResult result) {
  final response = result.stdout.toString().replaceAll('\r\n', '\n');
  final separator = response.indexOf('\n\n');
  final headers = separator < 0 ? response : response.substring(0, separator);
  final status = RegExp(r'^HTTP/\S+ (\d{3})').firstMatch(headers);
  if (status?[1] == '404') return null;
  if (result.exitCode != 0 || status?[1] != '200' || separator < 0) {
    throw StateError(
      'GitHub lookup failed: ${result.stderr.toString().trim()}',
    );
  }
  return jsonDecode(response.substring(separator + 2));
}

Future<Object?> githubApi(String path) async => parseGitHubResponse(
  await runGitHub(['api', '--include', path], const Duration(seconds: 60)),
);

Future<void> githubCommand(List<String> arguments) async {
  final result = await runGitHub(arguments, const Duration(seconds: 300));
  if (result.exitCode != 0) {
    throw ProcessException(
      'gh',
      arguments,
      '${result.stderr}',
      result.exitCode,
    );
  }
}

Future<String> remoteCommit(
  String repository,
  String tag,
  GitHubApi api,
) async {
  final reference = await api('repos/$repository/git/ref/tags/$tag') as Map?;
  if (reference == null) {
    throw StateError('The release tag is missing from GitHub.');
  }
  var target = reference['object'] as Map;
  for (var depth = 0; depth < 10; depth++) {
    if (target['type'] == 'commit') return target['sha'] as String;
    if (target['type'] != 'tag') break;
    final annotation =
        await api('repos/$repository/git/tags/${target['sha']}') as Map?;
    if (annotation == null) break;
    target = annotation['object'] as Map;
  }
  throw StateError('The remote release tag does not resolve to a commit.');
}

Future<Map?> findRelease(String repository, String tag, GitHubApi api) async {
  // Authenticated writers can see drafts in this listing.
  for (var page = 1; page <= 100; page++) {
    final releases = await api(
      'repos/$repository/releases?per_page=100&page=$page',
    );
    if (releases is! List) {
      throw StateError('GitHub did not return the repository releases.');
    }
    for (final release in releases.cast<Map>()) {
      if (release['tag_name'] == tag) return release;
    }
    if (releases.length < 100) return null;
  }
  throw StateError('Release lookup exceeded 100 pages.');
}

Future<void> publishRelease(
  Directory root,
  String tag,
  Directory output,
  String repository, {
  GitHubApi api = githubApi,
  GitHubCommand command = githubCommand,
}) async {
  final release = checkTag(root, tag);
  if (!RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(repository)) {
    throw StateError('Expected an owner/repository name.');
  }
  final plan = readReleaseJson(File('${output.path}/release-plan.json'));
  for (final entry in release.entries) {
    if (plan[entry.key] != entry.value) {
      throw StateError('The prepared release differs from this tag.');
    }
  }
  final prefix = 'legion-frontend-${release['version']}-x86_64';
  final expected = {
    '$prefix.AppImage',
    '$prefix-source.tar.gz',
    '$prefix.json',
    '$prefix-acceptance.tar.gz',
    'SHA256SUMS',
    ...debianNames(release),
  };
  final assets = plan['assets'] as Map;
  if (!sameNames(assets.keys, expected)) {
    throw StateError('The prepared release asset list differs.');
  }
  for (final entry in assets.entries) {
    if (releaseSha256(File('${output.path}/${entry.key}')) != entry.value) {
      throw StateError('Prepared release asset changed: ${entry.key}');
    }
  }
  final notes = File('${output.path}/RELEASE-NOTES.md');
  if (releaseSha256(notes) != plan['notes_sha256']) {
    throw StateError('Prepared release notes changed.');
  }
  if (await remoteCommit(repository, tag, api) != release['commit']) {
    throw StateError('The GitHub tag moved after the build.');
  }
  final existing = await findRelease(repository, tag, api);
  if (existing != null && existing['draft'] != true) {
    throw StateError(
      'This tag already has a published release; its assets are protected.',
    );
  }
  await command([
    'release',
    existing == null ? 'create' : 'edit',
    tag,
    '--repo',
    repository,
    '--title',
    tag,
    '--notes-file',
    notes.path,
    '--prerelease=${release['prerelease']}',
    if (existing == null) ...[
      '--draft',
      '--verify-tag',
      '--target',
      release['commit'] as String,
    ],
  ]);
  await command([
    'release',
    'upload',
    tag,
    '--repo',
    repository,
    '--clobber',
    for (final name in assets.keys) '${output.path}/$name',
  ]);
  verifyUploadedRelease(
    await findRelease(repository, tag, api),
    release,
    assets,
    output,
    draft: true,
  );
  if (await remoteCommit(repository, tag, api) != release['commit']) {
    throw StateError('The GitHub tag moved during the upload.');
  }
  await command([
    'release',
    'edit',
    tag,
    '--repo',
    repository,
    '--draft=false',
    '--prerelease=${release['prerelease']}',
    if (release['prerelease'] == true) '--latest=false',
  ]);
  verifyUploadedRelease(
    await findRelease(repository, tag, api),
    release,
    assets,
    output,
    draft: false,
  );
}

void verifyUploadedRelease(
  Map? uploaded,
  Map release,
  Map assets,
  Directory output, {
  required bool draft,
}) {
  if (uploaded == null ||
      uploaded['draft'] != draft ||
      uploaded['prerelease'] != release['prerelease']) {
    throw StateError(
      'GitHub did not retain the expected release status (draft: $draft).',
    );
  }
  final uploadedAssets = (uploaded['assets'] as List).cast<Map>();
  if (!sameNames(uploadedAssets.map((asset) => asset['name']), assets.keys)) {
    throw StateError(
      'GitHub changed the release asset filenames or inventory.',
    );
  }
  for (final asset in uploadedAssets) {
    final name = asset['name'] as String;
    if (asset['state'] != 'uploaded' ||
        asset['digest'] != 'sha256:${assets[name]}' ||
        asset['size'] != File('${output.path}/$name').lengthSync()) {
      throw StateError('GitHub release asset failed verification: $name');
    }
  }
}

Future<void> releaseMain(
  List<String> args,
  Directory root,
  Map<String, String> environment,
) async {
  final command = switch (args.firstOrNull) {
    'check-tag' when args.length == 2 => ReleaseCommand.checkTag,
    'prepare' when args.length == 4 => ReleaseCommand.prepare,
    'publish' when args.length == 3 => ReleaseCommand.publish,
    _ => throw const FormatException(
      'Usage: dart tool/release_workflow.dart '
      'check-tag TAG | prepare TAG INPUTS OUTPUT | publish TAG OUTPUT',
    ),
  };
  switch (command) {
    case ReleaseCommand.checkTag:
      final release = checkTag(root, args[1]);
      final output = environment['GITHUB_OUTPUT'];
      if (output != null && output.isNotEmpty) {
        File(output).writeAsStringSync(
          'tag=${release['tag']}\ncommit=${release['commit']}\n',
          mode: FileMode.append,
        );
      }
      stdout.writeln(jsonEncode(release));
    case ReleaseCommand.prepare:
      stdout.writeln(
        jsonEncode(
          prepareRelease(root, args[1], Directory(args[2]), Directory(args[3])),
        ),
      );
    case ReleaseCommand.publish:
      await publishRelease(
        root,
        args[1],
        Directory(args[2]),
        environment['GITHUB_REPOSITORY'] ?? '',
      );
  }
}

Future<void> main(List<String> args) async {
  try {
    await releaseMain(
      args,
      File.fromUri(Platform.script).parent.parent,
      Platform.environment,
    );
  } catch (error) {
    stderr.writeln('Release: $error');
    exitCode = 1;
  }
}
