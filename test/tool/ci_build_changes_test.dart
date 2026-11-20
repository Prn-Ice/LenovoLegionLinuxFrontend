@Tags(['tooling'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/git_fixture.dart';

void main() {
  final script = File('tool/ci_build_changes.sh').absolute.path;
  late Directory root;
  late GitFixture repository;
  late String base;

  String git(List<String> arguments) => repository.git(arguments);

  ProcessResult select({
    bool withBase = true,
    String? output,
    bool worktree = false,
    String? head,
  }) => Process.runSync(
    'bash',
    [
      script,
      if (withBase) ...['--base', base],
      if (worktree) '--worktree',
      if (head != null) ...['--head', head],
    ],
    workingDirectory: root.path,
    environment: {...repository.environment, 'GITHUB_OUTPUT': output ?? ''},
    includeParentEnvironment: false,
  );

  void commit() {
    git(['add', '-A']);
    git(['commit', '--allow-empty', '-m', 'fixture']);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('ci-changes-');
    addTearDown(() => root.deleteSync(recursive: true));
    repository = GitFixture(root);
    addTearDown(repository.dispose);
    repository.initialize(name: 'CI test');
    commit();
    base = git(['rev-parse', 'HEAD']);
  });

  const all = {'integration', 'lifecycle', 'nix', 'appimage', 'debian'};

  Set<String> selected({bool withBase = true}) {
    final result = select(withBase: withBase);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return (result.stdout as String)
        .trim()
        .split('\n')
        .where((line) => line.endsWith('=true') && !line.startsWith('tooling='))
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
      'control/package.nix',
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
    'tool/package_release.dart': {'nix', 'appimage', 'debian'},
    'tool/release_source/source_archive.dart': {'nix', 'appimage', 'debian'},
    'tool/record_package_test_results.dart': {'appimage', 'debian'},
    'tool/package_test_results.dart': {'appimage', 'debian'},
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

  test('release calls run every check and append GitHub output', () {
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

  test('app and documentation changes do not select tooling tests', () {
    for (final name in [
      'lib/features/fans/fans_page.dart',
      'test/features/fans/fans_page_test.dart',
      'assets/icon.svg',
      'README.md',
      'docs/nix.md',
    ]) {
      base = git(['rev-parse', 'HEAD']);
      change(name);
      expect(select().stdout, contains('tooling=false\n'), reason: name);
    }
  });

  test('tooling tests follow their scripts, fixtures, and shared inputs', () {
    for (final name in [
      'tool/check_commits.dart',
      'test/tool/check_commits_test.dart',
      'test/support/git_fixture.dart',
      'test/fixtures/git_fixture_probe.dart',
      'linux/CMakeLists.txt',
      '.githooks/pre-push',
      '.github/workflows/ci.yml',
      'packaging/nix/frontend.nix',
      'control/commands.cpp',
      'control/CMakeLists.txt',
      'pubspec.lock',
      'flake.lock',
      'dart_test.yaml',
      'test/flutter_test_config.dart',
      'analysis_options.yaml',
    ]) {
      base = git(['rev-parse', 'HEAD']);
      change(name);
      expect(select().stdout, contains('tooling=true\n'), reason: name);
    }
  });

  test('renaming a tool into documentation still selects tooling tests', () {
    change('tool/old.dart');
    base = git(['rev-parse', 'HEAD']);
    Directory('${root.path}/docs').createSync();
    File('${root.path}/tool/old.dart').renameSync('${root.path}/docs/old.md');
    commit();
    expect(select().stdout, contains('tooling=true\n'));
  });

  test('worktree mode includes staged, unstaged, and untracked tooling', () {
    change('tool/existing.dart');
    base = git(['rev-parse', 'HEAD']);
    final existing = File('${root.path}/tool/existing.dart')
      ..writeAsStringSync('unstaged\n');
    expect(select().stdout, contains('tooling=false\n'));
    expect(select(worktree: true).stdout, contains('tooling=true\n'));
    git(['add', 'tool/existing.dart']);
    expect(select(worktree: true).stdout, contains('tooling=true\n'));
    commit();
    base = git(['rev-parse', 'HEAD']);
    existing.deleteSync();
    expect(select(worktree: true).stdout, contains('tooling=true\n'));
    git(['restore', 'tool/existing.dart']);
    File('${root.path}/tool/new.dart').writeAsStringSync('untracked\n');
    expect(select(worktree: true).stdout, contains('tooling=true\n'));
  });

  test('worktree mode leaves untracked app changes outside tooling', () {
    Directory('${root.path}/lib').createSync();
    File('${root.path}/lib/new.dart').writeAsStringSync('app\n');
    expect(select(worktree: true).stdout, contains('tooling=false\n'));
  });

  test('worktree mode rejects a conflicting head option', () {
    expect(select(worktree: true, head: base).exitCode, 2);
  });
}
