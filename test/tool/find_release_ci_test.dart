import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/find_release_ci.dart';

void main() {
  const repository = 'owner/project';
  const commit = '0123456789012345678901234567890123456789';
  final now = DateTime.utc(2026, 11, 17);
  late Map<String, dynamic> run;
  late List<Map<String, dynamic>> artifacts;

  Future<int?> find() => findReleaseCi(
    repository: repository,
    commit: commit,
    now: now,
    read: (endpoint) async => endpoint.contains('/artifacts?')
        ? {'artifacts': artifacts}
        : {
            'workflow_runs': [run],
          },
  );

  setUp(() {
    run = {
      'id': 42,
      'repository': {'full_name': repository},
      'head_repository': {'full_name': repository},
      'path': '.github/workflows/ci.yml',
      'event': 'push',
      'head_branch': 'main',
      'head_sha': commit,
      'status': 'completed',
      'conclusion': 'success',
    };
    artifacts = [
      for (final name in ['appimage-ubuntu-22.04', 'debian-amd64'])
        {
          'name': name,
          'expired': false,
          'size_in_bytes': 100,
          'expires_at': '2027-01-01T00:00:00Z',
        },
    ];
  });

  test('selects completed main CI with both retained packages', () async {
    expect(await find(), 42);
  });

  for (final entry in {
    'head_sha': 'another-commit',
    'head_branch': 'feature',
    'event': 'pull_request',
    'path': '.github/workflows/other.yml',
    'status': 'in_progress',
    'conclusion': 'failure',
    'repository': {'full_name': 'another/repository'},
    'head_repository': {'full_name': 'fork/project'},
  }.entries) {
    test('rejects a mismatched ${entry.key}', () async {
      run[entry.key] = entry.value;
      expect(await find(), isNull);
    });
  }

  test('both packages must be present and usable', () async {
    for (final index in [0, 1]) {
      final original = artifacts[index];
      for (final change in [
        {'name': 'unrelated'},
        {'expired': true},
        {'size_in_bytes': 0},
        {'expires_at': '2026-01-01T00:00:00Z'},
      ]) {
        artifacts[index] = {...original, ...change};
        expect(await find(), isNull, reason: '$index $change');
      }
      artifacts[index] = original;
    }
    artifacts.removeLast();
    expect(await find(), isNull);
  });

  test('looks past missing packages to an earlier successful run', () async {
    final selected = await findReleaseCi(
      repository: repository,
      commit: commit,
      now: now,
      read: (endpoint) async {
        if (endpoint.contains('/runs/43/')) return {'artifacts': []};
        if (endpoint.contains('/runs/42/')) return {'artifacts': artifacts};
        expect(endpoint, contains('branch=main&event=push&status=success'));
        expect(endpoint, contains('head_sha=$commit'));
        return {
          'workflow_runs': [
            {...run, 'id': 43},
            run,
          ],
        };
      },
    );
    expect(selected, 42);
  });

  test('API failure falls back to release CI', () async {
    final scratch = Directory.systemTemp.createTempSync('release-ci-');
    addTearDown(() => scratch.deleteSync(recursive: true));
    final gh = File('${scratch.path}/gh')
      ..writeAsStringSync('#!/bin/sh\nexit 1\n');
    Process.runSync('chmod', ['+x', gh.path]);
    final result = await Process.run(
      'dart',
      ['tool/find_release_ci.dart'],
      environment: {
        'PATH': '${scratch.path}:${Platform.environment['PATH']}',
        'GITHUB_SHA': commit,
        'GITHUB_REPOSITORY': repository,
        'GITHUB_OUTPUT': '${scratch.path}/output',
        'GITHUB_STEP_SUMMARY': '${scratch.path}/summary',
      },
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stderr, contains('running release checks'));
    expect(File('${scratch.path}/output').readAsStringSync(), 'ci_run=\n');
  });
}
