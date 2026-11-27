@Tags(['tooling'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/packaging/package_release.dart';
import '../../tool/packaging/release_source/build_record.dart';
import '../../tool/packaging/release_source/linux_build.dart';
import '../../tool/packaging/release_source/source_archive.dart';
import '../../tool/packaging/release_source/source_inputs.dart';
import '../support/git_fixture.dart';

void main() {
  late Directory workspace;
  late Directory root;
  late Directory dependency;
  late Directory bundle;
  late ReleaseBuildRecord stamp;
  late GitFixture repository;

  void write(String path, String content) {
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  Future<ReleaseBuildRecord> recordBuild() async =>
      recordReleaseBuild(bundle, await captureReleaseInputs(root));

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('release source ');
    addTearDown(() => workspace.delete(recursive: true));
    root = Directory('${workspace.path}/app')..createSync();
    dependency = Directory('${workspace.path}/dependency')..createSync();
    bundle = Directory('${root.path}/build/bundle');
    write('${bundle.path}/lib/libapp.so', 'binary');
    write('${bundle.path}/libexec/legion-control-helper', 'helper');
    await _run(root, 'chmod', [
      '755',
      '${bundle.path}/libexec/legion-control-helper',
    ]);
    write('${dependency.path}/pubspec.yaml', 'name: handy_window');
    write('${dependency.path}/linux/libhandy/src/COPYING', 'license');
    write(
      '${root.path}/.dart_tool/package_config.json',
      jsonEncode({
        'packages': [
          {'name': 'app', 'rootUri': '../'},
          {'name': 'handy_window', 'rootUri': '../../dependency'},
        ],
      }),
    );
    write(
      '${root.path}/.dart_tool/package_graph.json',
      jsonEncode({
        'roots': ['app'],
        'packages': [
          {
            'name': 'app',
            'version': '1.0.0',
            'dependencies': ['handy_window'],
          },
          {'name': 'handy_window', 'version': '0.4.2', 'dependencies': []},
        ],
      }),
    );
    write('${root.path}/pubspec.lock', 'lock');
    write('${root.path}/README.md', 'source');
    write('${root.path}/.envrc', '# optional build environment');
    write('${root.path}/.gitignore', '/build/\n/.dart_tool/\n.env\n.beads/\n');
    write(
      '${root.path}/.gitattributes',
      '/inspiration export-ignore\n/.beads export-ignore\n/.env export-ignore\n/.env.* export-ignore\n/.agent export-ignore\n',
    );
    write('${root.path}/inspiration/reference.png', 'reference');
    write('${root.path}/.env', 'SECRET=do-not-ship');
    write('${root.path}/.beads/credentials', 'private');
    Directory('${root.path}/.agent').createSync();
    Link('${root.path}/.agent/local-skill').createSync('/private/home/skill');
    repository = GitFixture(root);
    addTearDown(repository.dispose);
    repository.initialize();
    repository.git(['add', '.']);
    repository.git(['add', '-f', '.env', '.beads/credentials']);
    repository.git(['commit', '-qm', 'fixture']);
    stamp = await recordBuild();
  });

  test(
    'resolves source archive options without losing spaces or absolute paths',
    () {
      expect(
        releaseSourceArchive([], root).path,
        '${root.path}/build/release/legion-frontend-source.tar.gz',
      );
      expect(
        releaseSourceArchive([
          '--output',
          'build/source archive.tar.gz',
        ], root).path,
        '${root.path}/build/source archive.tar.gz',
      );
      final absolute = '${workspace.path}/source archive.tar.gz';
      expect(releaseSourceArchive(['--output', absolute], root).path, absolute);
    },
  );

  test('the release CLI rejects malformed options before building', () async {
    final result = await Process.run('dart', [
      'tool/packaging/package_release.dart',
      '--output',
      '--unexpected',
    ]);
    expect(result.exitCode, 64);
    expect(
      result.stderr,
      contains('Usage: dart tool/packaging/package_release.dart'),
    );
    expect(result.stdout, isEmpty);
  });

  test(
    'a serialized build record still pairs the archive and static helper',
    () async {
      final recorded = await recordReleaseBuild(
        bundle,
        await captureReleaseInputs(root),
        staticHelper: true,
      );
      final json = jsonDecode(jsonEncode(recorded)) as Map<String, dynamic>;
      final restored = ReleaseBuildRecord.fromJson(json);
      final output = File('${root.path}/build/restored.tar.gz');
      final manifest = await packageReleaseSource(
        root,
        bundle,
        output,
        restored,
      );
      expect(manifest['format'], 4);
      expect(manifest['inputs'], json['inputs']);
      expect(manifest['binary_sha256'], json['binary_sha256']);
      expect(manifest['bundle'], json['bundle']);
      expect(manifest['build_config'], {
        'portable_control': true,
        'static_portable_helper': true,
      });
      final recipe = await _run(root, 'tar', [
        '-xOf',
        output.path,
        './REBUILD.md',
      ]);
      expect(
        recipe.stdout,
        contains('bash source/tool/packaging/build_static_helper.sh'),
      );
    },
  );

  test(
    'archives build sources, preserves edits/modes/links, and repeats exactly',
    () async {
      write('${dependency.path}/modified-cache-source.cc', 'local source edit');
      final executable = '${dependency.path}/linux/libhandy/src/tool.sh';
      write(executable, '#!/bin/sh\n');
      await _run(root, 'chmod', ['744', executable]);
      await Link('${dependency.path}/linux/libhandy/src/COPYING.link')
          .create('COPYING');
      Directory('${dependency.path}/empty').createSync();
      write('${dependency.path}/.git/config', 'private remote');
      write('${dependency.path}/.env', 'private environment');
      write('${dependency.path}/build/generated', 'generated output');
      write('${dependency.path}/linux/build/source.cc', 'nested build source');
      stamp = await recordBuild();
      final output = File('${root.path}/build/release.tar.gz');
      final manifest = await packageReleaseSource(root, bundle, output, stamp);
      expect((manifest['bundle'] as Map).keys, contains('./lib/libapp.so'));
      final listing = (await _run(root, 'tar', [
        '-tzf',
        output.path,
      ])).stdout.toString().split('\n');
      expect(
        listing,
        contains('./dependencies/handy_window/linux/libhandy/src/COPYING'),
      );
      expect(listing, contains('./source/.envrc'));
      for (final excluded in [
        '.env',
        '.beads',
        '.agent',
        'inspiration',
        '.dart_tool',
      ]) {
        expect(
          listing.any(
            (path) =>
                path == './source/$excluded' ||
                path.startsWith('./source/$excluded/'),
          ),
          isFalse,
        );
      }
      expect(
        listing.any((path) => path.startsWith('./dependencies/app/')),
        isFalse,
      );
      expect(
        listing.any(
          (path) => path.contains('/.git/') || path.endsWith('/.env'),
        ),
        isFalse,
      );
      final extracted = Directory('${workspace.path}/extracted')..createSync();
      await _run(root, 'tar', ['-xzf', output.path, '-C', extracted.path]);
      final archived = '${extracted.path}/dependencies/handy_window';
      expect(
        File('$archived/modified-cache-source.cc').readAsStringSync(),
        'local source edit',
      );
      expect(
        FileStat.statSync('$archived/linux/libhandy/src/tool.sh').mode & 0x1ff,
        0x1e4,
      );
      expect(
        Link('$archived/linux/libhandy/src/COPYING.link').targetSync(),
        'COPYING',
      );
      expect(Directory('$archived/empty').existsSync(), isTrue);
      expect(Directory('$archived/build').existsSync(), isFalse);
      expect(
        File('$archived/linux/build/source.cc').readAsStringSync(),
        'nested build source',
      );
      final overrides = jsonDecode(
        File('${extracted.path}/dependency-overrides.yaml').readAsStringSync(),
      ) as Map;
      expect(
        overrides['dependency_overrides']['handy_window']['path'],
        '../dependencies/handy_window',
      );
      final repeat = File('${root.path}/build/repeat.tar.gz');
      await packageReleaseSource(root, bundle, repeat, stamp);
      expect(repeat.readAsBytesSync(), output.readAsBytesSync());
    },
  );

  test('rejects a dependency edited after the build started', () async {
    write('${dependency.path}/linux/libhandy/src/COPYING', 'later edit');
    await expectLater(
      packageReleaseSource(
        root,
        bundle,
        File('${root.path}/build/release.tar.gz'),
        stamp,
      ),
      throwsStateError,
    );
  });

  test('rejects a helper replaced after the build', () async {
    write('${bundle.path}/libexec/legion-control-helper', 'approved helper');
    stamp = await recordBuild();
    write('${bundle.path}/libexec/legion-control-helper', 'replacement');
    await expectLater(
      packageReleaseSource(
        root,
        bundle,
        File('${root.path}/build/release.tar.gz'),
        stamp,
      ),
      throwsStateError,
    );
  });

  test('requires an executable helper in every release build', () async {
    final helper = File('${bundle.path}/libexec/legion-control-helper');
    await _run(root, 'chmod', ['644', helper.path]);
    await expectLater(recordBuild(), throwsStateError);
    await _run(root, 'chmod', ['755', helper.path]);
    await helper.writeAsString('');
    await expectLater(recordBuild(), throwsStateError);
    await helper.delete();
    await expectLater(recordBuild(), throwsStateError);
    await Link(helper.path).create('../lib/libapp.so');
    await expectLater(recordBuild(), throwsStateError);
  });

  test('rejects source pairing for a build without helper configuration', () {
    final json = stamp.toJson();
    json['build_config'] = {'portable_control': false};
    expect(() => ReleaseBuildRecord.fromJson(json), throwsStateError);
  });

  test('requires the whole bundle fingerprint for source pairing', () {
    final json = stamp.toJson()..remove('bundle');
    expect(() => ReleaseBuildRecord.fromJson(json), throwsStateError);
  });

  test('records the default helper and extra runtime source inputs', () async {
    final runtime = Directory('${workspace.path}/runtime-inputs')..createSync();
    write('${runtime.path}/runtime-source.tar.gz', 'runtime source archive');
    stamp = await recordReleaseBuild(bundle, await captureReleaseInputs(root));
    final archive = File('${root.path}/build/release.tar.gz');
    final manifest = await packageReleaseSource(
      root,
      bundle,
      archive,
      stamp,
      additionalSources: runtime,
    );
    expect((manifest['build_config'] as Map)['portable_control'], isTrue);
    expect(
      (manifest['release_inputs'] as Map).keys,
      contains('./runtime-source.tar.gz'),
    );
    final recipe = await _run(root, 'tar', [
      '-xOf',
      archive.path,
      './REBUILD.md',
    ]);
    expect(recipe.stdout, contains('flutter build linux --release --no-pub\n'));
    expect(recipe.stdout, isNot(contains('LLLF_ENABLE_PORTABLE_CONTROL')));
    expect(recipe.stdout, isNot(contains('cmake -S')));
    final source = await _run(root, 'tar', [
      '-xOf',
      archive.path,
      './release-inputs/runtime-source.tar.gz',
    ]);
    expect(source.stdout, 'runtime source archive');
  });

  test(
    'records SDK revisions without private paths or SDK package copies',
    () async {
      final sdk = Directory('${workspace.path}/private-sdk');
      final metadata = {
        'frameworkVersion': '3.47.9',
        'frameworkRevision': 'framework-commit',
        'engineRevision': 'engine-commit',
        'dartSdkVersion': '3.12.0',
        'flutterRoot': sdk.path,
      };
      write(
        '${sdk.path}/bin/flutter',
        "#!/bin/sh\nprintf '%s\\n' '${jsonEncode(metadata)}'\n",
      );
      await _run(root, 'chmod', ['755', '${sdk.path}/bin/flutter']);
      final config = File('${root.path}/.dart_tool/package_config.json');
      final configJson = jsonDecode(config.readAsStringSync()) as Map;
      (configJson['packages'] as List).addAll([
        {'name': 'flutter', 'rootUri': '${sdk.uri}packages/flutter/'},
        {
          'name': 'sky_engine',
          'rootUri': '${sdk.uri}bin/cache/pkg/sky_engine/',
        },
        {'name': 'dev_tool', 'rootUri': '${workspace.uri}absent-dev-tool/'},
      ]);
      config.writeAsStringSync(jsonEncode(configJson));
      final graph = File('${root.path}/.dart_tool/package_graph.json');
      final graphJson = jsonDecode(graph.readAsStringSync()) as Map;
      final packages = graphJson['packages'] as List;
      (packages.first['dependencies'] as List).add('flutter');
      packages.first['devDependencies'] = ['dev_tool'];
      packages.addAll([
        {
          'name': 'flutter',
          'version': '0.0.0',
          'dependencies': ['sky_engine'],
        },
        {'name': 'sky_engine', 'version': '0.0.0', 'dependencies': []},
        {'name': 'dev_tool', 'version': '1.0.0', 'dependencies': []},
      ]);
      graph.writeAsStringSync(jsonEncode(graphJson));
      stamp = await recordBuild();
      final manifest = await packageReleaseSource(
        root,
        bundle,
        File('${root.path}/build/release.tar.gz'),
        stamp,
      );
      final inputs = manifest['inputs'] as Map;
      expect((inputs['packages'] as Map).keys, ['handy_window']);
      expect(
        Map.of(inputs['flutter_sdk'] as Map)..remove('source_provenance'),
        Map.of(metadata)..remove('flutterRoot'),
      );
      expect((inputs['flutter_sdk'] as Map)['source_provenance'], {
        'status': 'notApplicable',
        'reason': 'The Flutter SDK is not installed from the Nix store.',
      });
      expect(jsonEncode(manifest), isNot(contains(workspace.path)));
    },
  );

  test('rejects a binary changed after the build', () async {
    write('${bundle.path}/lib/libapp.so', 'changed binary');
    await expectLater(
      packageReleaseSource(
        root,
        bundle,
        File('${root.path}/build/release.tar.gz'),
        stamp,
      ),
      throwsStateError,
    );
  });

  test('rejects an external dependency symlink', () async {
    await Link('${dependency.path}/outside').create('../private.txt');
    await expectLater(captureReleaseInputs(root), throwsStateError);
  });

  test('rejects untracked app source before packaging', () async {
    write('${root.path}/credentials.txt', 'secret');
    await expectLater(
      packageReleaseSource(
        root,
        bundle,
        File('${root.path}/build/release.tar.gz'),
        stamp,
      ),
      throwsStateError,
    );
  });
}

Future<ProcessResult> _run(
  Directory root,
  String executable,
  List<String> args,
) async {
  final result = await Process.run(
    executable,
    args,
    workingDirectory: root.path,
  );
  if (result.exitCode != 0) throw StateError(result.stderr.toString());
  return result;
}
