import 'dart:async';
import 'dart:convert';
import 'dart:io';

const portableTestUnit =
    'legion-bootstrap-probe-01234567-89ab-4cde-8fab-0123456789ab.service';
const portableTestAddress =
    'unix:path=/run/legion-bootstrap-probe-01234567-89ab-4cde-8fab-0123456789ab/control.sock';

/// Controlled child-process boundary for launcher and transport lifecycle tests.
class PortableHelperProcess implements Process {
  @override
  final int pid = 321;
  final output = StreamController<List<int>>();
  final errors = StreamController<List<int>>();
  final exit = Completer<int>();
  final listening = Completer<void>();
  final signals = <ProcessSignal>[];
  bool ignoreTerm = false;
  bool ignoreKill = false;

  @override
  Stream<List<int>> get stdout {
    if (!listening.isCompleted) listening.complete();
    return output.stream;
  }

  @override
  Stream<List<int>> get stderr => errors.stream;
  @override
  final IOSink stdin = _UnusedInput();
  @override
  Future<int> get exitCode => exit.future;

  void line(String value) => output.add(utf8.encode('$value\n'));
  void ready({bool acknowledgementFirst = true}) {
    line('SNAPSHOT_READY launcher=$pid unit=$portableTestUnit');
    if (acknowledgementFirst) line('START_ACKNOWLEDGED');
    line(
      'CONTROL_READY helper=123 unit=$portableTestUnit address=$portableTestAddress',
    );
    if (!acknowledgementFirst) line('START_ACKNOWLEDGED');
  }

  void finish([int code = 0]) {
    if (exit.isCompleted) return;
    unawaited(output.close());
    unawaited(errors.close());
    exit.complete(code);
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    signals.add(signal);
    if ((signal == ProcessSignal.sigterm && !ignoreTerm) ||
        (signal == ProcessSignal.sigkill && !ignoreKill)) {
      finish(-signal.signalNumber);
    }
    return true;
  }
}

class _UnusedInput implements IOSink {
  @override
  Future<void> close() async {}
  @override
  Future<void> get done async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('The launcher writes no input.');
}
