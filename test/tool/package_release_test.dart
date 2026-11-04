import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/package_release.dart';
import '../../tool/nix_flutter_provenance.dart';

void main() {
  test(
    'parses a Nix derivation chain without exposing source paths',
    nixProvenanceFixtureTest,
  );
  late Directory workspace;
  late Directory root;
  late Directory dependency;
  late Directory bundle;
  late Map<String, Object> stamp;

  void write(String path, String content) {
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  Future<Map<String, Object>> recordBuild() async => {
    'inputs': await captureReleaseInputs(root),
    'binary_sha256': await _sha256(File('${bundle.path}/lib/libapp.so')),
  };

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('release source ');
    addTearDown(() => workspace.delete(recursive: true));
    root = Directory('${workspace.path}/app')..createSync();
    dependency = Directory('${workspace.path}/dependency')..createSync();
    bundle = Directory('${root.path}/build/bundle');
    write('${bundle.path}/lib/libapp.so', 'binary');
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
    await _run(root, 'git', ['init', '-q']);
    await _run(root, 'git', ['config', 'user.email', 'test@example.invalid']);
    await _run(root, 'git', ['config', 'user.name', 'Test']);
    await _run(root, 'git', ['add', '.']);
    await _run(root, 'git', ['add', '-f', '.env', '.beads/credentials']);
    await _run(root, 'git', ['commit', '-qm', 'fixture']);
    stamp = await recordBuild();
  });

  test(
    'archives build sources, preserves edits/modes/links, and repeats exactly',
    () async {
      write('${dependency.path}/modified-cache-source.cc', 'local source edit');
      final executable = '${dependency.path}/linux/libhandy/src/tool.sh';
      write(executable, '#!/bin/sh\n');
      await _run(root, 'chmod', ['744', executable]);
      await Link(
        '${dependency.path}/linux/libhandy/src/COPYING.link',
      ).create('COPYING');
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
      final overrides =
          jsonDecode(
                File(
                  '${extracted.path}/dependency-overrides.yaml',
                ).readAsStringSync(),
              )
              as Map;
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
        (inputs['flutter_sdk'] as Map).keys,
        containsAll([
          'frameworkVersion',
          'frameworkRevision',
          'engineRevision',
          'dartSdkVersion',
          'source_provenance',
        ]),
      );
      expect((inputs['flutter_sdk'] as Map)['source_provenance'], {
        'status': 'unavailable',
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

void nixProvenanceFixtureTest() {
  final fetcher = '/nix/store/5fs9jmaj8bh58sdlm76zrmyrsrmr7h43-source.drv';
  final unwrapped =
      '/nix/store/4pc2g8z5qgzbshvfa4cya0cxk8j3ffq8-flutter-3.47.9-unwrapped.drv';
  final result = parseNixFlutterProvenance(
    {
      fetcher: {
        'structuredAttrs': {
          'owner': 'flutter',
          'repo': 'flutter',
          'rev': 'refs/tags/3.47.9',
          'urls': [
            'https://github.com/flutter/flutter/archive/refs/tags/3.47.9.tar.gz',
          ],
          'outputHash': 'sha256-JBauGMdb1lmply2yAekkeonIX7+duVFixiHEREg+EG8=',
          'outputHashMode': 'recursive',
        },
        'outputs': {
          'out': {
            'hash': 'sha256-JBauGMdb1lmply2yAekkeonIX7+duVFixiHEREg+EG8=',
          },
        },
      },
      unwrapped: {
        'structuredAttrs': {
          'src': '/nix/store/1gbc6jf4pnic6x2ijcfwamal6qw1kljy-source',
          'patches': ['/nix/store/patch-one', '/nix/store/patch-two'],
        },
      },
    },
    sdkDerivation:
        '/nix/store/dy4r1f6aavk1m4safx8pzacnff7f83cb-flutter-wrapped.drv',
  );
  expect(result['status'], 'recorded');
  expect((result['source'] as Map)['ref'], 'refs/tags/3.47.9');
  expect(jsonEncode(result), isNot(contains('/home/')));
}

Future<String> _sha256(File file) async {
  final result = await Process.run('sha256sum', ['--zero', file.path]);
  if (result.exitCode != 0) throw StateError(result.stderr.toString());
  return result.stdout.toString().substring(0, 64);
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
