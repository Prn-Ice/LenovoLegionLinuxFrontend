import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late Directory fixtureParent;
  late File callLog;
  late File flutter;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('journey_runner_test_');
    fixtureParent = await Directory(
      '${directory.path}/temporary fixtures',
    ).create();
    await File('${fixtureParent.path}/keep.txt').writeAsString('unrelated');
    callLog = File('${directory.path}/calls.log');
    flutter = File('${directory.path}/fake flutter');
    await flutter.writeAsString(r'''#!/usr/bin/env bash
set -euo pipefail
phase=$2
fixture=''
for argument in "$@"; do
  case "$argument" in
    --dart-define=LLLF_GCC_RESTART_FIXTURE=*)
      fixture=${argument#--dart-define=LLLF_GCC_RESTART_FIXTURE=}
      ;;
  esac
done
printf '%s\t%s\n' "$phase" "$fixture" >> "$RUNNER_CALL_LOG"
case "$phase" in
  integration_test/app_test.dart)
    [[ -z "$fixture" ]]
    ;;
  integration_test/restart_setup.dart)
    [[ -d "$fixture" ]]
    printf 'saved data' > "$fixture/phase-marker"
    ;;
  integration_test/restart_verify.dart)
    [[ $(cat "$fixture/phase-marker") == 'saved data' ]]
    ;;
  *) exit 91 ;;
esac
if [[ "$phase" == "${FAIL_PHASE:-}" ]]; then
  exit 37
fi
''');
    final chmod = await Process.run('chmod', ['+x', flutter.path]);
    expect(chmod.exitCode, 0, reason: '${chmod.stderr}');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  Future<ProcessResult> run({String? failPhase}) => Process.run(
    'bash',
    ['tool/test_linux_journeys.sh'],
    environment: {
      'FLUTTER': flutter.path,
      'TMPDIR': fixtureParent.path,
      'RUNNER_CALL_LOG': callLog.path,
      'FAIL_PHASE': failPhase ?? '',
    },
  );

  Future<void> expectCleanup() async {
    final remaining = await fixtureParent.list().toList();
    expect(remaining.map((entry) => entry.path), [
      '${fixtureParent.path}/keep.txt',
    ]);
    expect(
      await File('${fixtureParent.path}/keep.txt').readAsString(),
      'unrelated',
    );
  }

  test(
    'runs separate restart phases with shared storage and cleans up',
    () async {
      final result = await run();
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final calls = (await callLog.readAsLines())
          .map((line) => line.split('\t'))
          .toList();
      expect(calls.map((call) => call.first), [
        'integration_test/app_test.dart',
        'integration_test/restart_setup.dart',
        'integration_test/restart_verify.dart',
      ]);
      expect(calls[0][1], isEmpty);
      final root = calls[1][1];
      expect(root, startsWith('${fixtureParent.path}/lllf-gcc-restart.'));
      expect(calls[2][1], root);
      expect(await Directory(root).exists(), isFalse);
      await expectCleanup();
    },
  );

  for (final phase in [
    'integration_test/app_test.dart',
    'integration_test/restart_setup.dart',
    'integration_test/restart_verify.dart',
  ]) {
    test('stops and cleans up when $phase fails', () async {
      final result = await run(failPhase: phase);
      expect(result.exitCode, 37, reason: '${result.stderr}');
      final calls = await callLog.readAsLines();
      expect(calls.last.split('\t').first, phase);
      expect(calls.where((line) => line.startsWith('$phase\t')), hasLength(1));
      await expectCleanup();
    });
  }
}
