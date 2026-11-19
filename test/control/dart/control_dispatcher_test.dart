import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../control/dart/control_dispatcher.dart';
import '../../../control/dart/managed_command.dart';

class _Operation implements ManagedCommandOperation {
  _Operation() {
    result = _result.future;
  }

  final _result = Completer<ManagedCommandResult>();
  @override
  late final Future<ManagedCommandResult> result;
  bool cancelled = false;

  @override
  void cancel() {
    cancelled = true;
  }

  void complete([
    ManagedCommandResult value = const ManagedCommandResult(
      status: ManagedCommandStatus.success,
    ),
  ]) {
    _result.complete(value);
  }

  void completeError(Object error) => _result.completeError(error);
}

void main() {
  late Directory directory;
  late List<(String, List<String>, int)> calls;
  late List<_Operation> operations;
  late ControlDispatcher dispatcher;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('dispatcher-test-');
    calls = [];
    operations = [];
    dispatcher = ControlDispatcher(
      cli: '/trusted/legion_cli',
      sessionDirectory: directory,
      execute: (executable, arguments, runtime) {
        calls.add((executable, arguments, runtime));
        final operation = _Operation();
        operations.add(operation);
        return operation;
      },
    );
    await dispatcher.call('Authorize', const []);
  });

  tearDown(() async {
    await dispatcher.close();
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  test('builds exact generic, graphics, and payload commands', () async {
    final generic = dispatcher.call('SetFeature', const [
      'PlatformProfileFeature',
      'quiet',
    ]);
    expect(calls.single.$1, '/trusted/legion_cli');
    expect(calls.single.$2, [
      '--donotexpecthwmon',
      'set-feature',
      'PlatformProfileFeature',
      'quiet',
    ]);
    expect(calls.single.$3, 10);
    operations.single.complete();
    expect((await generic).isSuccess, isTrue);

    final graphics = dispatcher.call('SetGraphicsMode', const ['discrete']);
    expect(calls[1].$1, '/trusted/legion_cli');
    expect(calls[1].$2, [
      '--donotexpecthwmon',
      'graphics-mode',
      'set',
      'discrete',
      '--json',
    ]);
    expect(calls[1].$3, 35);
    operations[1].complete();
    await graphics;

    final payloadReply = dispatcher.call('ApplyFanCurve', <Object>[
      [1, 2, 3],
    ]);
    final payloadPath = calls[2].$2.last;
    expect(calls[2].$2.first, 'fancurve-write-file-to-hw');
    expect(calls[2].$3, 10);
    expect(File(payloadPath).existsSync(), isTrue);
    expect(FileStat.statSync(payloadPath).mode & 0x1ff, 0x180);
    operations[2].complete();
    expect((await payloadReply).isSuccess, isTrue);
    expect(File(payloadPath).existsSync(), isFalse);
  });

  test(
    'applies exit-status precedence for generic and graphics commands',
    () async {
      final unavailable = dispatcher.call('SetFeature', const [
        'PlatformProfileFeature',
        'quiet',
      ]);
      operations.single.complete(
        const ManagedCommandResult(
          status: ManagedCommandStatus.commandFailed,
          exitStatus: 2,
          output: [0xc3, 0x28],
        ),
      );
      final unavailableReply = await unavailable;
      expect(unavailableReply.errorName, 'Unavailable');
      expect(unavailableReply.errorMessage, contains('\uFFFD'));

      final unsupported = dispatcher.call('SetFeature', const [
        'PlatformProfileFeature',
        'quiet',
      ]);
      operations[1].complete(
        const ManagedCommandResult(
          status: ManagedCommandStatus.commandFailed,
          exitStatus: 3,
        ),
      );
      expect((await unsupported).errorName, 'NotSupported');

      final blocked = dispatcher.call('SetGraphicsMode', const ['discrete']);
      operations[2].complete(
        const ManagedCommandResult(
          status: ManagedCommandStatus.commandFailed,
          exitStatus: 2,
        ),
      );
      expect((await blocked).errorName, 'GraphicsBlocked');

      final pending = dispatcher.call('SetGraphicsMode', const ['discrete']);
      operations[3].complete(
        const ManagedCommandResult(
          status: ManagedCommandStatus.commandFailed,
          exitStatus: 3,
        ),
      );
      expect((await pending).errorName, 'GraphicsPending');
    },
  );

  test(
    'runner statuses override exit status and latch cleanup failure',
    () async {
      for (final status in [
        ManagedCommandStatus.outputLimit,
        ManagedCommandStatus.timeout,
        ManagedCommandStatus.cleanupFailed,
      ]) {
        final request = dispatcher.call('SetFeature', const [
          'PlatformProfileFeature',
          'quiet',
        ]);
        operations.last.complete(
          ManagedCommandResult(status: status, exitStatus: 2),
        );
        final reply = await request;
        expect(reply.errorName, switch (status) {
          ManagedCommandStatus.timeout => 'Timeout',
          ManagedCommandStatus.cleanupFailed => 'Unavailable',
          _ => 'CommandFailed',
        });
        if (status == ManagedCommandStatus.cleanupFailed) {
          final next = await dispatcher.call('SetFeature', const [
            'PlatformProfileFeature',
            'quiet',
          ]);
          expect(next.errorName, 'Unavailable');
          expect(operations.length, 3);
        }
      }
    },
  );

  test('rejects invalid payload bytes before conversion', () async {
    final reply = await dispatcher.call('ApplyFanCurve', <Object>[
      [-1, 256],
    ]);
    expect(reply.errorName, 'InvalidArgs');
    expect(calls, isEmpty);
  });

  test('validation precedes Busy and Busy cleans a payload', () async {
    final first = dispatcher.call('SetFeature', const [
      'PlatformProfileFeature',
      'quiet',
    ]);
    final invalid = await dispatcher.call('SetFeature', const ['bad']);
    expect(invalid.errorName, 'InvalidArgs');

    final busy = dispatcher.call('ApplyFanCurve', <Object>[
      [1],
    ]);
    expect((await busy).errorName, 'Busy');
    expect(
      directory.listSync().whereType<Directory>().every(
        (child) => child.listSync().isEmpty,
      ),
      isTrue,
    );
    operations.first.complete();
    await first;
  });

  test('cleans payload when runner throws and when operation fails', () async {
    final throwing = ControlDispatcher(
      cli: '/trusted/legion_cli',
      sessionDirectory: directory,
      execute: (executable, arguments, runtime) =>
          throw StateError('start failed'),
    );
    await throwing.call('Authorize', const []);
    final reply = await throwing.call('ApplyFanCurve', <Object>[
      [1, 2],
    ]);
    expect(reply.errorName, 'Unavailable');
    expect(directory.listSync(), isEmpty);
    await throwing.close();
  });

  test(
    'maps operation result exceptions to Unavailable and cleans payload',
    () async {
      final failed = dispatcher.call('ApplyFanCurve', <Object>[
        [1, 2],
      ]);
      final path = calls.single.$2.last;
      operations.single.completeError(StateError('completion failed'));
      final reply = await failed;
      expect(reply.errorName, 'Unavailable');
      expect(File(path).existsSync(), isFalse);
    },
  );

  test('close cancels and waits for controlled completion', () async {
    final pending = dispatcher.call('SetFeature', const [
      'PlatformProfileFeature',
      'quiet',
    ]);
    final operation = operations.single;
    final closeDone = Completer<void>();
    final closing = dispatcher.close();
    expect(operation.cancelled, isTrue);
    closing.then((_) => closeDone.complete());
    expect(closeDone.isCompleted, isFalse);
    operation.complete();
    await closing;
    expect((await pending).errorName, 'Unavailable');
    expect(dispatcher.active, isFalse);
  });
}
