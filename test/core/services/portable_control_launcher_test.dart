import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/services/legion_control_client.dart';
import 'package:legion_frontend/core/services/portable_control_launcher.dart';

import '../../support/portable_helper_process.dart';

void main() {
  late PortableHelperProcess process;
  late PortableControlLauncher launcher;
  void createFixture({
    Duration startupTimeout = const Duration(seconds: 20),
    Duration stopTimeout = const Duration(seconds: 3),
  }) {
    process = PortableHelperProcess();
    launcher = PortableControlLauncher(
      executable: '/bundle with spaces/libexec/legion-portable-control',
      startupTimeout: startupTimeout,
      stopTimeout: stopTimeout,
      startProcess:
          (
            _,
            _, {
            required environment,
            required workingDirectory,
            required includeParentEnvironment,
          }) async => process,
    );
  }

  setUp(() => createFixture());
  tearDown(() => launcher.close());

  test(
    'starts one fixed helper with a host environment and neutral working directory',
    () async {
      var starts = 0;
      launcher = PortableControlLauncher(
        executable: '/bundle with spaces/helper',
        environment: const {
          'HOME': '/home/example',
          'DISPLAY': ':1',
          'PATH': '/app/bin',
          'LD_PRELOAD': '/app/code.so',
          'LD_AUDIT': '/app/audit.so',
          'GIO_EXTRA_MODULES': '/app/gio',
          'PYTHONPATH': '/app/python',
          'DBUS_SYSTEM_BUS_ADDRESS': 'unix:path=/app/bus',
          'APPDIR': '/app',
        },
        startProcess:
            (
              executable,
              arguments, {
              required environment,
              required workingDirectory,
              required includeParentEnvironment,
            }) async {
              starts++;
              expect(executable, '/bundle with spaces/helper');
              expect(arguments, ['--control']);
              expect(workingDirectory, '/');
              expect(includeParentEnvironment, isFalse);
              expect(environment, {
                'HOME': '/home/example',
                'DISPLAY': ':1',
                'PATH':
                    '/run/current-system/sw/bin:/usr/sbin:/usr/bin:/sbin:/bin',
              });
              return process;
            },
      );
      final first = launcher.start();
      final second = launcher.start();
      await process.listening.future;
      process.ready();
      final endpoint = await first;
      expect(await second, same(endpoint));
      expect(endpoint.address, portableTestAddress);
      expect(endpoint.helperPid, 123);
      expect(starts, 1);
    },
  );

  test(
    'waits for acknowledgement even if root readiness arrives first',
    () async {
      final starting = launcher.start();
      await process.listening.future;
      process.ready(acknowledgementFirst: false);
      expect((await starting).unit, portableTestUnit);
    },
  );

  test(
    'rejects the wrong launcher PID before publishing an endpoint',
    () async {
      final rejected = expectLater(
        launcher.start(),
        throwsA(isA<LegionControlSetupException>()),
      );
      await process.listening.future;
      process.line('SNAPSHOT_READY launcher=999 unit=$portableTestUnit');
      await rejected;
      expect(process.signals, [ProcessSignal.sigterm]);
    },
  );

  test('rejects an endpoint from another session directory', () async {
    final rejected = expectLater(
      launcher.start(),
      throwsA(isA<LegionControlSetupException>()),
    );
    await process.listening.future;
    process.line(
      'SNAPSHOT_READY launcher=${process.pid} unit=$portableTestUnit',
    );
    process.line('START_ACKNOWLEDGED');
    process.line(
      'CONTROL_READY helper=123 unit=$portableTestUnit address=unix:path=/tmp/other.sock',
    );
    await rejected;
  });

  test(
    'rejects invalid UTF-8 and overlong lines without growing buffers',
    () async {
      for (final bytes in [
        [0xff, 10],
        List.filled(4097, 65),
      ]) {
        final child = PortableHelperProcess();
        final owner = PortableControlLauncher(
          executable: '/bundle/helper',
          startProcess:
              (
                _,
                _, {
                required environment,
                required workingDirectory,
                required includeParentEnvironment,
              }) async => child,
        );
        final rejected = expectLater(
          owner.start(),
          throwsA(isA<LegionControlSetupException>()),
        );
        await child.listening.future;
        child.output.add(bytes);
        await rejected;
        await owner.close();
        expect(child.signals, [ProcessSignal.sigterm]);
      }
    },
  );

  test('rejects excessive diagnostics', () async {
    final rejected = expectLater(
      launcher.start(),
      throwsA(isA<LegionControlSetupException>()),
    );
    await process.listening.future;
    process.errors.add(List.filled(8193, 65));
    await rejected;
  });

  test('reports denial after draining final stderr', () async {
    final rejected = expectLater(
      launcher.start(),
      throwsA(isA<LegionControlPermissionDeniedException>()),
    );
    await process.listening.future;
    process.errors.add(
      utf8.encode(
        'GDBus.Error:org.freedesktop.DBus.Error.AccessDenied: denied',
      ),
    );
    process.finish(1);
    await rejected;
  });

  test('closing while spawn is pending stops the late child', () async {
    final spawned = Completer<Process>();
    launcher = PortableControlLauncher(
      executable: '/bundle/helper',
      startProcess:
          (
            _,
            _, {
            required environment,
            required workingDirectory,
            required includeParentEnvironment,
          }) => spawned.future,
    );
    final rejected = expectLater(
      launcher.start(),
      throwsA(isA<LegionControlUnavailableException>()),
    );
    await launcher.close();
    await rejected;
    spawned.complete(process);
    await process.exitCode;
    await launcher.close();
    expect(process.signals, [ProcessSignal.sigterm]);
  });

  test(
    'startup timeout stops the process and rejects late readiness',
    () async {
      createFixture(startupTimeout: Duration.zero);
      final rejected = expectLater(
        launcher.start(),
        throwsA(isA<LegionControlTimeoutException>()),
      );
      await rejected;
      expect(process.signals, [ProcessSignal.sigterm]);
    },
  );

  test('shutdown escalates to SIGKILL when SIGTERM is ignored', () async {
    createFixture(stopTimeout: Duration.zero);
    process.ignoreTerm = true;
    final ready = launcher.start();
    await process.listening.future;
    process.ready();
    await ready;
    final closing = launcher.close();
    await closing;
    expect(process.signals, [ProcessSignal.sigterm, ProcessSignal.sigkill]);
  });

  test(
    'a missing helper produces setup guidance and cannot be retried in that session',
    () async {
      launcher = PortableControlLauncher(
        executable: '/missing/helper',
        startProcess:
            (
              _,
              _, {
              required environment,
              required workingDirectory,
              required includeParentEnvironment,
            }) async => throw const ProcessException(
              '/missing/helper',
              [],
              'not found',
              2,
            ),
      );
      await expectLater(
        launcher.start(),
        throwsA(isA<LegionControlSetupException>()),
      );
      await expectLater(
        launcher.start(),
        throwsA(isA<LegionControlUnavailableException>()),
      );
    },
  );
}
