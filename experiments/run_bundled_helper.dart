import 'dart:ffi';
import 'dart:io';

import 'check_bundled_dart_runtime.dart' as runtime_checks;

final class PollDescriptor extends Struct {
  @Int32()
  external int descriptor;

  @Int16()
  external int events;

  @Int16()
  external int returnedEvents;
}

/// Reads the process pinned by an inherited Linux process handle.
int readPinnedProcess(int descriptor) {
  final fields = File('/proc/self/fdinfo/$descriptor').readAsLinesSync();
  final process = fields.firstWhere((line) => line.startsWith('Pid:'));
  final processId = int.parse(process.substring(4).trim());
  if (processId <= 1) {
    throw StateError('The inherited process handle has already exited.');
  }
  return processId;
}

/// Waits on the two inherited process handles, without looking up reusable PIDs.
void waitForAppExit(DynamicLibrary symbols) {
  final allocate = symbols
      .lookupFunction<
        Pointer<Void> Function(UintPtr, UintPtr),
        Pointer<Void> Function(int, int)
      >('calloc');
  final release = symbols
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('free');
  final poll = symbols
      .lookupFunction<
        Int32 Function(Pointer<PollDescriptor>, UintPtr, Int32),
        int Function(Pointer<PollDescriptor>, int, int)
      >('poll');
  final errorNumber = symbols
      .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
        '__errno_location',
      );
  final handles = allocate(2, sizeOf<PollDescriptor>()).cast<PollDescriptor>();
  if (handles == nullptr) {
    throw StateError('Could not allocate the process-handle check.');
  }
  try {
    handles[0]
      ..descriptor = 0
      ..events = 1;
    handles[1]
      ..descriptor = 3
      ..events = 1;
    final elapsed = Stopwatch()..start();
    while (elapsed.elapsed < const Duration(seconds: 45)) {
      final ready = poll(handles, 2, 500);
      if (ready < 0) {
        if (errorNumber().value == 4) continue; // Linux EINTR.
        throw OSError(
          'Could not observe the app lifetime.',
          errorNumber().value,
        );
      }
      for (var index = 0; index < 2; index++) {
        final events = handles[index].returnedEvents;
        if ((events & (8 | 32)) != 0) {
          throw StateError('An inherited process handle is invalid.');
        }
        if ((events & (1 | 16)) != 0) return;
      }
    }
    throw StateError('The prototype exceeded its app-lifetime deadline.');
  } finally {
    release(handles.cast());
  }
}

/// Runs only inside the disposable VM, after the native starter approves it.
Future<void> main(List<String> arguments) async {
  try {
    final marker = File('/etc/legion-control-lifecycle-test-vm');
    if (!marker.existsSync() ||
        marker.readAsStringSync().trim() !=
            'legion-control-disposable-lifecycle-vm' ||
        arguments.length != 3) {
      throw StateError('This helper prototype runs only in the test VM.');
    }
    final unit = arguments[0];
    if (!RegExp(r'^legion-bootstrap-probe-[0-9a-f-]{36}\.service$')
        .hasMatch(unit)) {
      throw const FormatException('Invalid prototype service name.');
    }
    final appProcess = int.parse(arguments[1]);
    final appUser = int.parse(arguments[2]);
    final symbols = DynamicLibrary.process();
    final userId = symbols.lookupFunction<Uint32 Function(), int Function()>(
      'getuid',
    );
    if (userId() != 0 || appUser <= 0 || readPinnedProcess(0) != appProcess) {
      throw StateError('The helper identity or app process does not match.');
    }
    final launcherProcess = readPinnedProcess(3);
    final runtime = '/run/${unit.substring(0, unit.length - 8)}/dart';
    final mappings = File('/proc/self/maps')
        .readAsLinesSync()
        .where((line) => line.contains('/'))
        .map((line) => line.substring(line.indexOf('/')));
    if (mappings.isEmpty ||
        mappings.any((file) => !file.startsWith('$runtime/'))) {
      throw StateError('The helper loaded code outside its protected bundle.');
    }
    await runtime_checks.main();
    if (exitCode != 0) return;
    stdout.writeln(
      'DART_BUNDLE_READY uid=0 pid=$pid unit=$unit app=$appProcess '
      'launcher=$launcherProcess runtime=$runtime',
    );
    await stdout.flush();
    waitForAppExit(symbols);
    stdout.writeln('DART_BUNDLE_EXIT app session ended');
    await stdout.flush();
  } catch (error) {
    stdout.writeln('DART_BUNDLE_ERROR $error');
    exitCode = 1;
  }
}
