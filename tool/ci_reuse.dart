// Reuse successful checks for the exact checkout through GitHub's Actions API.
import 'dart:convert';
import 'dart:io';

enum CiCheck {
  test('Flutter Test & Analyze'),
  native('Native services and tests'),
  lifecycle('Control lifecycle and portable startup VMs'),
  integration('Linux native app integration'),
  nix('Nix frontend build and acceptance'),
  appimageBuild('AppImage build and source companion', 'appimage-build'),
  appimage(
    'AppImage build and Ubuntu/NixOS acceptance',
    'appimage-ubuntu-22.04',
  ),
  debianBuild('Debian build and source companion', 'debian-build'),
  debian('Debian package build and acceptance', 'debian-amd64');

  const CiCheck(this.label, [this.artifact]);
  final String label;
  final String? artifact;

  String get key => switch (this) {
    CiCheck.appimageBuild => 'appimage_build',
    CiCheck.debianBuild => 'debian_build',
    _ => name,
  };

  String marker(String commit) => 'ci-pass-v1-$key-$commit';
}

typedef ReadGitHub = Future<Map<String, dynamic>> Function(String endpoint);

Future<List<Map<String, dynamic>>> githubItems(
  ReadGitHub read,
  String endpoint,
  String field,
) async {
  final items = <Map<String, dynamic>>[];
  for (var page = 1; ; page++) {
    final separator = endpoint.contains('?') ? '&' : '?';
    final response = await read('$endpoint${separator}per_page=100&page=$page');
    final batch = (response[field] as List).cast<Map<String, dynamic>>();
    items.addAll(batch);
    if (batch.length < 100) return items;
  }
}

bool usableArtifact(Map artifact, DateTime now) =>
    artifact['expired'] == false &&
    artifact['size_in_bytes'] is int &&
    (artifact['size_in_bytes'] as int) > 0 &&
    DateTime.parse(artifact['expires_at'] as String).isAfter(now);

bool artifactFromJob(Map artifact, Map job) {
  final created = DateTime.parse(artifact['created_at'] as String);
  final started = DateTime.parse(job['started_at'] as String);
  final completed = DateTime.parse(job['completed_at'] as String);
  return !created.isBefore(started) && !created.isAfter(completed);
}

bool trustedRun(
  Map run, {
  required String repository,
  required String commit,
  int? pullRequest,
  String? headCommit,
}) {
  if (run['repository']?['full_name'] != repository ||
      run['head_repository']?['full_name'] != repository) {
    return false;
  }
  final path = run['path'];
  if (run['event'] == 'push' && run['head_sha'] == commit) {
    return (path == '.github/workflows/ci.yml' &&
            run['head_branch'] == 'main') ||
        (path == '.github/workflows/release.yml' &&
            (run['head_branch'] as String).startsWith('v'));
  }
  // PR markers bind the synthetic merge SHA, not the API's PR head SHA.
  // Never accept these markers outside the same PR or from a fork.
  return pullRequest != null &&
      run['event'] == 'pull_request' &&
      path == '.github/workflows/ci.yml' &&
      run['head_sha'] == headCommit &&
      (run['pull_requests'] as List).any(
        (pr) => (pr as Map)['number'] == pullRequest,
      );
}

Future<Map<CiCheck, int>> selectReusableChecks({
  required ReadGitHub read,
  required String repository,
  required String commit,
  required DateTime now,
  int? pullRequest,
  String? headCommit,
}) async {
  final selected = <CiCheck, int>{};
  final runs = <int, Map<String, dynamic>>{};
  final jobs = <int, List<Map<String, dynamic>>>{};
  final artifacts = <int, List<Map<String, dynamic>>>{};
  final base = 'repos/$repository/actions';
  for (final check in CiCheck.values) {
    final marker = check.marker(commit);
    final candidates = await githubItems(
      read,
      '$base/artifacts?name=$marker',
      'artifacts',
    );
    for (final candidate in candidates) {
      if (candidate['name'] != marker || !usableArtifact(candidate, now)) {
        continue;
      }
      final runId = (candidate['workflow_run'] as Map)['id'] as int;
      final run = runs[runId] ??= await read('$base/runs/$runId');
      if (!trustedRun(
        run,
        repository: repository,
        commit: commit,
        pullRequest: pullRequest,
        headCommit: headCommit,
      )) {
        continue;
      }
      final runJobs = jobs[runId] ??= await githubItems(
        read,
        '$base/runs/$runId/jobs?filter=all',
        'jobs',
      );
      final passedJobs = runJobs
          .where(
            (job) =>
                job['conclusion'] == 'success' &&
                (job['name'] == check.label ||
                    (job['name'] as String).endsWith(' / ${check.label}')) &&
                artifactFromJob(candidate, job),
          )
          .toList();
      if (passedJobs.isEmpty) continue;
      if (check.artifact != null) {
        final runArtifacts = artifacts[runId] ??= await githubItems(
          read,
          '$base/runs/$runId/artifacts',
          'artifacts',
        );
        if (!runArtifacts.any(
          (artifact) =>
              artifact['name'] == check.artifact &&
              usableArtifact(artifact, now) &&
              passedJobs.any((job) => artifactFromJob(artifact, job)),
        )) {
          continue;
        }
      }
      selected[check] = runId;
      break;
    }
  }
  return selected;
}

Future<Map<String, dynamic>> readGitHub(String endpoint) async {
  final result = await Process.run('gh', ['api', endpoint]);
  if (result.exitCode != 0) {
    throw StateError('GitHub API lookup failed: ${result.stderr}');
  }
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

Future<void> main() async {
  final env = Platform.environment;
  final commit = env['GITHUB_SHA']!;
  final repository = env['GITHUB_REPOSITORY']!;
  final event =
      jsonDecode(await File(env['GITHUB_EVENT_PATH']!).readAsString()) as Map;
  final pr = event['pull_request'] as Map?;
  var selected = <CiCheck, int>{};
  try {
    selected = await selectReusableChecks(
      read: readGitHub,
      repository: repository,
      commit: commit,
      now: DateTime.now().toUtc(),
      pullRequest: pr?['number'] as int?,
      headCommit: pr?['head']?['sha'] as String?,
    );
  } catch (error) {
    // API failures must cost time, not silently remove required coverage.
    stderr.writeln(
      'Could not verify previous checks; running them again: $error',
    );
  }
  final outputs = StringBuffer();
  final summary = StringBuffer('### Exact-commit check reuse\n\n');
  for (final check in CiCheck.values) {
    final run = selected[check];
    outputs.writeln('${check.key}_run=${run ?? ''}');
    if (run != null) {
      summary.writeln(
        '- ${check.label}: [run $run](https://github.com/$repository/actions/runs/$run)',
      );
    }
  }
  if (selected.isEmpty) {
    summary.writeln('No reusable checks found for `$commit`.');
  }
  stdout.write(outputs);
  await File(env['GITHUB_OUTPUT']!)
      .writeAsString(outputs.toString(), mode: FileMode.append);
  await File(env['GITHUB_STEP_SUMMARY']!)
      .writeAsString(summary.toString(), mode: FileMode.append);
}
