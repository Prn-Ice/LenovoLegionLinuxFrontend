import 'dart:async';

// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../control/dart/control_commands.dart';
import '../../../control/dart/managed_command.dart';
import '../../../control/dart/portable_cli.dart';

class _QualificationOperation implements ManagedCommandOperation {
  final completer = Completer<ManagedCommandResult>();
  bool cancelled = false;

  @override
  Future<ManagedCommandResult> get result => completer.future;

  @override
  void cancel() {
    cancelled = true;
    completer.complete(const ManagedCommandResult());
  }
}

void main() {
  test('accepts the complete interactive command group', () {
    final help = '--donotexpecthwmon {${interactiveCliCommands.join(' ')}}';
    expect(validatePortableCliHelp(help), isNull);
  });

  test('rejects a command that is only a substring match', () {
    final help =
        '--donotexpecthwmon {${interactiveCliCommands.join(' ').replaceFirst('graphics-mode', 'graphics-mode-extra')}}';
    expect(validatePortableCliHelp(help), contains('graphics-mode'));
  });

  test('uses UTF-8 bytes for the help output limit', () {
    final help = '\u{1f600}' * 16_385;
    expect(validatePortableCliHelp(help), contains('excessive'));
  });

  test('cancels qualification when the session dies', () {
    fakeAsync((async) {
      var alive = true;
      final operation = _QualificationOperation();
      Object? failure;
      qualifyPortableCli(
        execute: (executable, arguments, runtime) => operation,
        cli: '/trusted/legion_cli',
        sessionIsAlive: () => alive,
      ).catchError((Object error) {
        failure = error;
        return const QualificationResult(false);
      });
      alive = false;
      async.elapse(const Duration(milliseconds: 50));
      async.flushMicrotasks();
      expect(operation.cancelled, isTrue);
      expect(failure, isA<StateError>());
    });
  });
}
