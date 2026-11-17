// Find a successful main CI run whose packages match the tagged commit.
import 'dart:convert';
import 'dart:io';

Future<int?> findReleaseCi({
  required String repository,
  required String commit,
  required DateTime now,
  required Future<Map> Function(String endpoint) read,
}) async {
  final base = 'repos/$repository/actions';
  final response = await read(
    '$base/workflows/ci.yml/runs?branch=main&event=push'
    '&status=success&head_sha=$commit&per_page=20',
  );
  for (final run in response['workflow_runs'] as List) {
    if (run['repository']?['full_name'] != repository ||
        run['head_repository']?['full_name'] != repository ||
        run['path'] != '.github/workflows/ci.yml' ||
        run['event'] != 'push' ||
        run['head_branch'] != 'main' ||
        run['head_sha'] != commit ||
        run['status'] != 'completed' ||
        run['conclusion'] != 'success') {
      continue;
    }
    final id = run['id'] as int;
    final response = await read('$base/runs/$id/artifacts?per_page=100');
    final available = {
      for (final artifact in response['artifacts'] as List)
        if (artifact['expired'] == false &&
            (artifact['size_in_bytes'] as int) > 0 &&
            DateTime.parse(artifact['expires_at'] as String).isAfter(now))
          artifact['name'],
    };
    if (available.containsAll({'appimage-ubuntu-22.04', 'debian-amd64'})) {
      return id;
    }
  }
  return null;
}

Future<void> main() async {
  final env = Platform.environment;
  final repository = env['GITHUB_REPOSITORY']!;
  int? run;
  try {
    run = await findReleaseCi(
      repository: repository,
      commit: env['GITHUB_SHA']!,
      now: DateTime.now().toUtc(),
      read: (endpoint) async {
        final result = await Process.run('gh', ['api', endpoint]);
        if (result.exitCode != 0) throw StateError('${result.stderr}');
        return jsonDecode(result.stdout as String) as Map;
      },
    );
  } catch (error) {
    stderr.writeln('Could not verify main CI; running release checks: $error');
  }
  await File(env['GITHUB_OUTPUT']!)
      .writeAsString('ci_run=${run ?? ''}\n', mode: FileMode.append);
  await File(env['GITHUB_STEP_SUMMARY']!).writeAsString(
    run == null
        ? 'No completed main CI with both packages found; running release CI.\n'
        : 'Using [main CI run $run](https://github.com/$repository/actions/runs/$run) for this exact commit.\n',
    mode: FileMode.append,
  );
}
