import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final script = File('tool/ci_build_changes.sh').absolute.path;
  late Directory root;
  late String base;

  String git(List<String> arguments) {
    final result = Process.runSync(
      'git',
      arguments,
      workingDirectory: root.path,
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return '${result.stdout}'.trim();
  }

  ProcessResult select({bool withBase = true, String? output}) =>
      Process.runSync(
        'bash',
        [
          script,
          if (withBase) ...['--base', base],
        ],
        workingDirectory: root.path,
        environment: {'GITHUB_OUTPUT': ?output},
      );

  void commit() {
    git(['add', '-A']);
    git(['commit', '--allow-empty', '-m', 'fixture']);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('ci-changes-');
    git(['init']);
    git(['config', 'user.name', 'CI test']);
    git(['config', 'user.email', 'test@example.invalid']);
    commit();
    base = git(['rev-parse', 'HEAD']);
  });
  tearDown(() => root.deleteSync(recursive: true));

  const all = {'integration', 'lifecycle', 'nix', 'appimage', 'debian'};

  Set<String> selected({bool withBase = true}) {
    final result = select(withBase: withBase);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return (result.stdout as String)
        .trim()
        .split('\n')
        .where((line) => line.endsWith('=true'))
        .map((line) => line.split('=').first)
        .toSet();
  }

  void change(String name) {
    File('${root.path}/$name')
      ..createSync(recursive: true)
      ..writeAsStringSync('input\n');
    commit();
  }

  test('documentation and unit tests skip expensive checks', () {
    for (final name in [
      'README.md',
      'docs/nix.md',
      'AGENTS.md',
      'test/tool/ci_build_changes_test.dart',
      'analysis_options.yaml',
    ]) {
      File('${root.path}/$name')
        ..createSync(recursive: true)
        ..writeAsStringSync('documentation\n');
    }
    commit();
    expect(selected(), isEmpty);
  });

  test('shared native inputs and workflows select every expensive check', () {
    for (final name in [
      'control/test/fixtures.nix',
      'telemetry/package.nix',
      'pubspec.lock',
      '.github/workflows/ci.yml',
      'tool/new_build_tool.sh',
    ]) {
      base = git(['rev-parse', 'HEAD']);
      change(name);
      expect(selected(), all, reason: name);
    }
  });

  final cases = <String, Set<String>>{
    'lib/main.dart': {'integration', 'nix', 'appimage', 'debian'},
    'assets/icon.svg': {'integration', 'nix', 'appimage', 'debian'},
    'linux/CMakeLists.txt': {'integration', 'nix', 'appimage', 'debian'},
    'integration_test/app_test.dart': {'integration'},
    'tool/test_linux_journeys.sh': {'integration'},
    'packaging/debian/legion_frontend': {'debian'},
    'tool/build_deb.sh': {'debian'},
    'tool/package_deb.dart': {'debian'},
    'tool/package_appimage.dart': {'appimage'},
    'tool/test_appimage_nixos.sh': {'appimage'},
    'packaging/appimage/Dockerfile': {'appimage', 'debian', 'nix'},
    'packaging/nix/frontend.nix': {'nix', 'lifecycle', 'appimage'},
    'flake.lock': {'nix', 'lifecycle', 'appimage'},
    'tool/nix_flutter_provenance.dart': {'nix', 'appimage', 'debian'},
    'tool/test_portable_distro.sh': {'nix', 'appimage', 'debian'},
    'THIRD_PARTY_NOTICES.md': {'nix', 'appimage', 'debian'},
    'tool/release_workflow.dart': {},
  };
  for (final entry in cases.entries) {
    test('${entry.key} selects its consumers', () {
      change(entry.key);
      expect(selected(), entry.value);
    });
  }

  test('renames and deletions retain build paths', () {
    final source = File('${root.path}/lib/old.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('original\n');
    commit();
    base = git(['rev-parse', 'HEAD']);
    Directory('${root.path}/docs').createSync();
    source.renameSync('${root.path}/docs/old.md');
    commit();
    expect(selected(), {'integration', 'nix', 'appimage', 'debian'});
    final deleted = File('${root.path}/lib/deleted.dart')
      ..writeAsStringSync('remove me\n');
    commit();
    base = git(['rev-parse', 'HEAD']);
    deleted.deleteSync();
    commit();
    expect(selected(), {'integration', 'nix', 'appimage', 'debian'});
  });

  test('main and tag calls run every check and append GitHub output', () {
    final output = File('${root.path}/output')
      ..writeAsStringSync('previous=yes\n');
    final result = select(withBase: false, output: output.path);
    expect(result.exitCode, 0);
    expect(selected(withBase: false), all);
    expect(output.readAsStringSync(), 'previous=yes\n${result.stdout}');
  });

  test('invalid refs fail instead of skipping checks', () {
    base = 'missing-commit';
    expect(select().exitCode, isNot(0));
  });
}
