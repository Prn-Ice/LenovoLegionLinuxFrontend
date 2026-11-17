import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/ci_reuse.dart';

void main() {
  const repository = 'owner/project';
  const commit = '0123456789012345678901234567890123456789';
  final now = DateTime.utc(2026, 11, 17);
  late Map<String, dynamic> run;
  late List<Map<String, dynamic>> markers;
  late List<Map<String, dynamic>> jobs;
  late List<Map<String, dynamic>> packages;
  late List<String> requests;

  Map<String, dynamic> artifact(String name, {int runId = 42}) => {
    'name': name,
    'expired': false,
    'size_in_bytes': 100,
    'expires_at': '2027-01-01T00:00:00Z',
    'created_at': '2026-11-16T12:01:00Z',
    'workflow_run': {'id': runId},
  };

  Future<Map<String, dynamic>> read(String endpoint) async {
    requests.add(endpoint);
    if (endpoint.contains('/artifacts?name=')) {
      final name = Uri.parse('https://api.github.com/$endpoint')
          .queryParameters['name'];
      return {
        'artifacts': markers.where((item) => item['name'] == name).toList(),
      };
    }
    if (endpoint.contains('/jobs?')) return {'jobs': jobs};
    if (endpoint.contains('/artifacts?')) return {'artifacts': packages};
    return run;
  }

  Future<Map<CiCheck, int>> select({int? pr, String? head}) =>
      selectReusableChecks(
        read: read,
        repository: repository,
        commit: commit,
        now: now,
        pullRequest: pr,
        headCommit: head,
      );

  setUp(() {
    run = {
      'repository': {'full_name': repository},
      'head_repository': {'full_name': repository},
      'path': '.github/workflows/ci.yml',
      'event': 'push',
      'head_branch': 'main',
      'head_sha': commit,
      'pull_requests': <Map>[],
      // A failed overall run may still contain independently passed jobs.
      'conclusion': 'failure',
    };
    markers = [
      for (final check in CiCheck.values) artifact(check.marker(commit)),
    ];
    jobs = [
      for (final check in CiCheck.values)
        {
          'name': check.label,
          'conclusion': 'success',
          'started_at': '2026-11-16T12:00:00Z',
          'completed_at': '2026-11-16T12:02:00Z',
        },
    ];
    packages = [
      artifact('appimage-ubuntu-22.04'),
      artifact('appimage-build'),
      artifact('debian-build'),
      artifact('debian-amd64'),
    ];
    requests = [];
  });

  test(
    'reuses passed jobs and package artifacts from the exact main commit',
    () async {
      expect(await select(), {for (final check in CiCheck.values) check: 42});
      expect(requests.where((path) => path.endsWith('/runs/42')), hasLength(1));
      expect(requests.where((path) => path.contains('/jobs?')), hasLength(1));
      expect(
        requests.where((path) => path.contains('/runs/42/artifacts?')),
        hasLength(1),
      );
    },
  );

  test('reuses nested jobs from an earlier tag workflow', () async {
    run['path'] = '.github/workflows/release.yml';
    run['head_branch'] = 'v1.0.0';
    jobs = [
      for (final job in jobs)
        {...job, 'name': 'Release checks and artifacts / ${job['name']}'},
    ];
    expect(await select(), hasLength(CiCheck.values.length));
  });

  for (final mutation in <String, void Function()>{
    'different checkout': () => run['head_sha'] = 'another-commit',
    'feature branch': () => run['head_branch'] = 'feature',
    'unknown workflow': () => run['path'] = '.github/workflows/other.yml',
    'manual workflow': () => run['event'] = 'workflow_dispatch',
    'another repository': () => run['repository'] = {'full_name': 'other/repo'},
    'fork': () => run['head_repository'] = {'full_name': 'fork/project'},
  }.entries) {
    test('rejects results from ${mutation.key}', () async {
      mutation.value();
      expect(await select(), isEmpty);
    });
  }

  test('PR successes stay in the same PR and head commit', () async {
    run['event'] = 'pull_request';
    run['head_sha'] = 'pr-head';
    run['pull_requests'] = [
      {'number': 7},
    ];
    expect(
      await select(pr: 7, head: 'pr-head'),
      hasLength(CiCheck.values.length),
    );
    expect(await select(pr: 8, head: 'pr-head'), isEmpty);
    expect(await select(pr: 7, head: 'new-head'), isEmpty);
    expect(await select(), isEmpty);
  });

  test(
    'a PR head success cannot stand in for its synthetic merge commit',
    () async {
      run['event'] = 'pull_request';
      run['head_sha'] = 'pr-head';
      run['pull_requests'] = [
        {'number': 7},
      ];
      markers = [artifact(CiCheck.test.marker('pr-head'))];
      expect(await select(pr: 7, head: 'pr-head'), isEmpty);
    },
  );

  test('failed, cancelled, and skipped jobs are not passed checks', () async {
    for (final status in ['failure', 'cancelled', 'skipped', null]) {
      jobs = [
        for (final check in CiCheck.values)
          {'name': check.label, 'conclusion': status},
      ];
      expect(await select(), isEmpty, reason: '$status');
    }
  });

  test(
    'missing, expired, and empty package artifacts force only their rebuild',
    () async {
      for (final artifact in [
        null,
        {...packages.first, 'expired': true},
        {...packages.first, 'expires_at': '2026-01-01T00:00:00Z'},
        {...packages.first, 'size_in_bytes': 0},
      ]) {
        packages = [?artifact, packages.last];
        final selected = await select();
        expect(selected.containsKey(CiCheck.appimage), isFalse);
        expect(selected[CiCheck.debian], 42);
        expect(selected[CiCheck.test], 42);
      }
    },
  );

  test('expired or absent success markers force checks to run', () async {
    markers = [
      {...markers.first, 'expired': true},
      {...markers[1], 'expires_at': '2026-01-01T00:00:00Z'},
    ];
    expect(await select(), isEmpty);
  });

  test(
    'a passed build survives failed acceptance for the same commit',
    () async {
      jobs = [
        for (final job in jobs)
          if (job['name'] == CiCheck.appimage.label)
            {...job, 'conclusion': 'failure'}
          else
            job,
      ];
      final selected = await select();
      expect(selected[CiCheck.appimageBuild], 42);
      expect(selected.containsKey(CiCheck.appimage), isFalse);
    },
  );

  test(
    'a marker from a failed rerun cannot use an earlier passed job',
    () async {
      markers = [
        {...markers.first, 'created_at': '2026-11-16T13:01:00Z'},
      ];
      jobs.add({
        'name': CiCheck.test.label,
        'conclusion': 'failure',
        'started_at': '2026-11-16T13:00:00Z',
        'completed_at': '2026-11-16T13:02:00Z',
      });
      expect(await select(), isEmpty);
    },
  );

  test(
    'replacement artifacts from a failed rerun cannot reuse old approval',
    () async {
      packages[0] = {...packages.first, 'created_at': '2026-11-16T13:01:00Z'};
      final selected = await select();
      expect(selected.containsKey(CiCheck.appimage), isFalse);
      expect(selected[CiCheck.debian], 42);
    },
  );

  test('looks past an untrusted candidate for a trusted result', () async {
    markers.insert(0, artifact(CiCheck.test.marker(commit), runId: 99));
    Future<Map<String, dynamic>> withUntrusted(String endpoint) async =>
        endpoint.endsWith('/runs/99')
        ? {...run, 'head_branch': 'feature'}
        : read(endpoint);
    final selected = await selectReusableChecks(
      read: withUntrusted,
      repository: repository,
      commit: commit,
      now: now,
    );
    expect(selected[CiCheck.test], 42);
  });

  test('paginates GitHub lists without losing the query filter', () async {
    final endpoints = <String>[];
    final items = await githubItems(
      (endpoint) async {
        endpoints.add(endpoint);
        return {
          'artifacts': endpoint.endsWith('page=1')
              ? List.generate(100, (index) => {'id': index})
              : [
                  {'id': 100},
                ],
        };
      },
      'repos/owner/project/actions/artifacts?name=marker',
      'artifacts',
    );
    expect(items, hasLength(101));
    expect(endpoints.last, contains('name=marker&per_page=100&page=2'));
  });

  test(
    'CLI writes empty outputs on API failure instead of dropping checks',
    () async {
      final scratch = Directory.systemTemp.createTempSync('ci-reuse-');
      addTearDown(() => scratch.deleteSync(recursive: true));
      File('${scratch.path}/event.json').writeAsStringSync('{}');
      final gh = File('${scratch.path}/gh')
        ..writeAsStringSync('#!/bin/sh\nexit 1\n');
      Process.runSync('chmod', ['+x', gh.path]);
      final result = await Process.run(
        'dart',
        ['tool/ci_reuse.dart'],
        environment: {
          'PATH': '${scratch.path}:${Platform.environment['PATH']}',
          'GITHUB_SHA': commit,
          'GITHUB_REPOSITORY': repository,
          'GITHUB_EVENT_PATH': '${scratch.path}/event.json',
          'GITHUB_OUTPUT': '${scratch.path}/output',
          'GITHUB_STEP_SUMMARY': '${scratch.path}/summary',
        },
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stderr, contains('running them again'));
      expect(File('${scratch.path}/output').readAsLinesSync(), [
        for (final check in CiCheck.values) '${check.key}_run=',
      ]);
    },
  );

  test('workflow jobs and markers match the selector contract', () {
    final workflow = File('.github/workflows/ci.yml').readAsStringSync();
    for (final check in CiCheck.values) {
      expect(workflow, contains('name: ${check.label}'));
      expect(workflow, contains('check: ${check.key}\n'));
      expect(
        workflow,
        contains("needs.changes.outputs.${check.key}_run == ''"),
      );
    }
    expect(workflow, isNot(contains('flutter test test/tool')));
    expect(workflow, isNot(contains('  portable-ubuntu:')));
    final action = File('.github/actions/ci-success/action.yml')
        .readAsStringSync();
    expect(action, contains('ci-pass-v1-'));
    final release = File('.github/workflows/release.yml').readAsStringSync();
    for (final format in ['appimage', 'debian']) {
      expect(
        release,
        contains('run-id: \${{ needs.checks.outputs.${format}_run }}'),
      );
    }
  });
}
