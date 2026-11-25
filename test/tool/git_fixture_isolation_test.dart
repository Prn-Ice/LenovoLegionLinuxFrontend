@Tags(['tooling'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/git_fixture.dart';

Map<String, String> snapshot(Directory root) => {
  for (final file in root.listSync(recursive: true).whereType<File>())
    file.path.substring(root.path.length): base64Encode(file.readAsBytesSync()),
};

void main() {
  late Directory workspace;
  late GitFixture sentinel;
  late Map<String, String> hostileEnvironment;
  late Map<String, String> original;
  late File hookMarker;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('git-isolation-');
    addTearDown(() => workspace.deleteSync(recursive: true));
    sentinel = GitFixture(Directory('${workspace.path}/sentinel'));
    addTearDown(sentinel.dispose);
    sentinel.initialize(name: 'Sentinel owner');
    File('${sentinel.root.path}/README.md').writeAsStringSync('sentinel\n');
    sentinel.git(['add', '.']);
    sentinel.git(['commit', '-qm', 'Sentinel history']);
    original = snapshot(sentinel.root);
    hookMarker = File('${workspace.path}/hook-ran');
    final hooks = Directory('${workspace.path}/hooks')..createSync();
    final hook = File('${hooks.path}/pre-commit')
      ..writeAsStringSync('#!/bin/sh\ntouch "${hookMarker.path}"\nexit 1\n');
    expect(Process.runSync('chmod', ['+x', hook.path]).exitCode, 0);
    final global = File('${workspace.path}/global.config')
      ..writeAsStringSync('''
[user]
  name = Host identity
  email = host@example.invalid
[core]
  hooksPath = ${hooks.path}
  fsmonitor = ${hook.path}
[commit]
  gpgSign = true
[tag]
  gpgSign = true
[init]
  templateDir = ${hooks.path}
''');
    hostileEnvironment = {
      ...Platform.environment,
      'GIT_DIR': '${sentinel.root.path}/.git',
      'GIT_COMMON_DIR': '${sentinel.root.path}/.git',
      'GIT_WORK_TREE': sentinel.root.path,
      'GIT_INDEX_FILE': '${sentinel.root.path}/.git/index',
      'GIT_OBJECT_DIRECTORY': '${sentinel.root.path}/.git/objects',
      'GIT_CONFIG': '${sentinel.root.path}/.git/config',
      'GIT_CONFIG_GLOBAL': global.path,
      'GIT_CONFIG_COUNT': '1',
      'GIT_CONFIG_KEY_0': 'core.bare',
      'GIT_CONFIG_VALUE_0': 'true',
      'GIT_CONFIG_PARAMETERS': "'user.name=Injected identity'",
      'GIT_AUTHOR_NAME': 'Injected author',
      'GIT_AUTHOR_EMAIL': 'injected@example.invalid',
      'GIT_TEMPLATE_DIR': hooks.path,
    };
  });

  void expectSentinelUnchanged() {
    expect(snapshot(sentinel.root), original);
    expect(hookMarker.existsSync(), isFalse);
  }

  test('Dart Git fixtures and explicit-root tools ignore hook pointers', () {
    final result = Process.runSync(
      'dart',
      [
        '--packages=${File('.dart_tool/package_config.json').absolute.path}',
        File('test/fixtures/git_fixture_probe.dart').absolute.path,
        workspace.path,
      ],
      workingDirectory: workspace.path,
      environment: hostileEnvironment,
      includeParentEnvironment: false,
    );
    expectSentinelUnchanged();
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('the tag fixture ignores inherited pointers before bare init', () {
    // Stop at the first app call, after both repositories and a signed commit.
    // Full tag-app behavior is covered by the Nix release-tag check.
    final result = Process.runSync(
      'bash',
      [File('test/tool/tag_test.sh').absolute.path, 'bash', '-c', 'exit 37'],
      workingDirectory: workspace.path,
      environment: hostileEnvironment,
      includeParentEnvironment: false,
    );
    expectSentinelUnchanged();
    expect(result.exitCode, 37, reason: '${result.stdout}\n${result.stderr}');
  });
}
