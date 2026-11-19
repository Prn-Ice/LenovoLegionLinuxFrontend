@Tags(['tooling'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final script = File('tool/record_sleep_events.sh').absolute.path;
  final storage = File('tool/sleep_event_storage.sh').absolute.path;
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('sleep-recorder-'));
  tearDown(() => root.deleteSync(recursive: true));

  test(
    'filters routine polling but retains sleep, errors and kernel events',
    () {
      for (final (message, keep) in [
        ('prop_devname: /dev/i2c-20', false),
        ('PrepareForSleep(true)', true),
        ('There are no outputs', true),
        ('Failed', true),
        ('Idle timeout', true),
        ('Power button', true),
      ]) {
        final event = jsonEncode({
          'SYSLOG_IDENTIFIER': 'org_kde_powerdevil',
          'MESSAGE': message,
        });
        final result = Process.runSync('bash', [
          '-c',
          'source "$storage"; printf "%s\\n" "\$1" | keep_event',
          'filter',
          event,
        ]);
        expect(result.exitCode, keep ? 0 : 1, reason: message);
      }
      expect(
        Process.runSync('bash', [
          '-c',
          'source "$storage"; echo \'{"MESSAGE":"kernel"}\' | keep_event',
        ]).exitCode,
        0,
      );
    },
  );

  test('saved JSON files stay private and rotation stays bounded', () {
    final result = Process.runSync('bash', [
      '-c',
      '''
set -euo pipefail
umask 077
source "\$1"
directory=\$2
max_bytes=45
for ((index=0; index<20; index++)); do
  append_event "\$directory" "\$max_bytes" "\$(jq -cn --argjson index "\$index" '{index:\$index,message:"evidence"}')"
done
''',
      'storage',
      storage,
      root.path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final files = root.listSync().whereType<File>().toList();
    expect(files, hasLength(4));
    final latest = File('${root.path}/events.jsonl');
    expect((jsonDecode(latest.readAsStringSync()) as Map)['index'], 19);
    for (final file in files) {
      expect(file.lengthSync(), lessThanOrEqualTo(45));
      expect(file.statSync().mode & 0x3f, 0);
    }
    final oversized = Process.runSync('bash', [
      '-c',
      'source "\$1"; append_event "\$2" 1 \'{"message":"large"}\'',
      'storage',
      storage,
      root.path,
    ]);
    expect(oversized.exitCode, 1);
    expect(oversized.stderr, contains('exceeds the file size limit'));
    expect((jsonDecode(latest.readAsStringSync()) as Map)['index'], 19);
  });

  test(
    'records events and reports journal failure without touching hardware',
    () async {
      final journal = File('${root.path}/journalctl')
        ..writeAsStringSync('''#!/bin/sh
printf '%s\\n' "\$@" >"\$JOURNAL_ARGUMENTS"
echo '{"MESSAGE":"PM: hibernation entry","_TRANSPORT":"kernel"}'
exit "\${FAKE_JOURNAL_EXIT:-0}"
''');
      expect(Process.runSync('chmod', ['700', journal.path]).exitCode, 0);
      for (final code in [0, 1]) {
        final state = Directory('${root.path}/state-$code');
        final arguments = File('${root.path}/arguments');
        final result = await Process.run(
          'bash',
          [script],
          environment: {
            'PATH': '${root.path}:${Platform.environment['PATH']}',
            'XDG_STATE_HOME': state.path,
            'JOURNAL_ARGUMENTS': arguments.path,
            'FAKE_JOURNAL_EXIT': '$code',
          },
        ).timeout(const Duration(seconds: 10));
        expect(result.exitCode, code, reason: '${result.stderr}');
        expect(result.stdout, contains('Journal events are being saved'));
        final command = arguments.readAsLinesSync();
        expect(
          command,
          containsAll(['--follow', '_TRANSPORT=kernel', '_COMM=kwin_wayland']),
        );
        expect(command, isNot(contains('sudo')));
        final logs = state
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('events.jsonl'))
            .toList();
        expect(logs, hasLength(1));
        expect(logs.single.statSync().mode & 0x3f, 0);
        final events = logs.single
            .readAsLinesSync()
            .map((line) => jsonDecode(line) as Map)
            .toList();
        expect(events.first, contains('recorder_started'));
        expect(events[1]['MESSAGE'], 'PM: hibernation entry');
        expect(events.last['saved_events'], 1);
        if (code != 0) {
          expect(result.stderr, contains('journalctl stopped with exit 1'));
        }
      }
    },
  );

  test(
    'empty or malformed journal output fails and retains stop metadata',
    () async {
      final journal = File('${root.path}/journalctl');
      for (final (name, content) in [
        ('empty', ''),
        ('malformed', 'not JSON'),
      ]) {
        journal.writeAsStringSync('#!/bin/sh\nprintf "%s" \'$content\'\n');
        expect(Process.runSync('chmod', ['700', journal.path]).exitCode, 0);
        final state = Directory('${root.path}/$name');
        final result = await Process.run(
          'bash',
          [script],
          environment: {
            'PATH': '${root.path}:${Platform.environment['PATH']}',
            'XDG_STATE_HOME': state.path,
          },
        ).timeout(const Duration(seconds: 10));
        expect(result.exitCode, 1);
        final log = state.listSync(recursive: true).whereType<File>().single;
        final events = log
            .readAsLinesSync()
            .map((line) => jsonDecode(line) as Map)
            .toList();
        expect(events.last['saved_events'], 0);
        expect(events.last, contains('recorder_stopped'));
      }
    },
  );

  for (final writable in [true, false]) {
    test(
      writable
          ? 'termination stops the journal child and records the final count'
          : 'termination reports a failed final write',
      () async {
        final journal = File('${root.path}/journalctl')
          ..writeAsStringSync('''#!/bin/sh
echo '{"MESSAGE":"PM: hibernation entry","_TRANSPORT":"kernel"}'
trap 'exit 0' TERM
while :; do sleep 1; done
''');
        expect(Process.runSync('chmod', ['700', journal.path]).exitCode, 0);
        final state = Directory('${root.path}/state');
        final process = await Process.start(
          'bash',
          [script],
          environment: {
            'PATH': '${root.path}:${Platform.environment['PATH']}',
            'XDG_STATE_HOME': state.path,
          },
        );
        final errors = process.stderr.transform(utf8.decoder).join();
        final ready = Completer<void>();
        final output = process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              if (line.contains('Journal events are being saved') &&
                  !ready.isCompleted) {
                ready.complete();
              }
            });
        try {
          await ready.future.timeout(const Duration(seconds: 10));
          final log = state
              .listSync(recursive: true)
              .whereType<File>()
              .singleWhere((file) => file.path.endsWith('/events.jsonl'));
          final saved = writable ? log : log.renameSync('${log.path}.saved');
          if (!writable) Directory(log.path).createSync();
          expect(process.kill(ProcessSignal.sigterm), isTrue);
          expect(
            await process.exitCode.timeout(const Duration(seconds: 8)),
            writable ? 0 : 1,
            reason: await errors,
          );
          final events = saved
              .readAsLinesSync()
              .map((line) => jsonDecode(line) as Map)
              .toList();
          if (writable) {
            expect(events.last['saved_events'], 1);
          } else {
            expect(events, hasLength(2));
            expect(events.last['MESSAGE'], 'PM: hibernation entry');
          }
        } finally {
          process.kill(ProcessSignal.sigterm);
          try {
            await process.exitCode.timeout(const Duration(seconds: 8));
          } on TimeoutException {
            process.kill(ProcessSignal.sigkill);
            await process.exitCode;
          }
          await output.cancel();
        }
      },
    );
  }
}
