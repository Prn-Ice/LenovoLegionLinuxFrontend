import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';

import 'control_dispatcher.dart';
import 'linux_resources.dart';
import 'managed_command.dart';
import 'peer_server.dart';
import 'portable_cli.dart';
import 'systemd_bus.dart';

/// Runs the app's approved private control session after native protected startup.
Future<void> main(List<String> arguments) async {
  DBusClient? manager;
  ControlPeerServer? peer;
  ControlDispatcher? dispatcher;
  Timer? lifetime;
  final signals = <StreamSubscription<ProcessSignal>>[];
  try {
    final linux = LinuxResources();
    final session = _readSession(arguments, linux);
    bool alive() => linux.processAlive(0) && linux.processAlive(3);
    final ended = Completer<void>();
    void finish() {
      if (!ended.isCompleted) ended.complete();
    }

    for (final signal in [ProcessSignal.sigterm, ProcessSignal.sigint]) {
      signals.add(signal.watch().listen((_) => finish()));
    }
    manager = DBusClient(DBusAddress('unix:path=/run/dbus/system_bus_socket'));
    await manager.getId().timeout(const Duration(seconds: 3));
    final cli = linux.findHostCli();
    DBusClient openCommandBus() => SystemdBusClient(
      libraryPath: '${session.directory}/dart/lib/libsystemd.so.0',
      address: 'unix:path=/run/dbus/system_bus_socket',
    );
    final qualifier = ManagedCommandRunner(
      openBus: openCommandBus,
      parentUnit: session.unit,
    );
    final qualified = await qualifyPortableCli(
      execute: qualifier.start,
      cli: cli,
      sessionIsAlive: () => !ended.isCompleted && alive(),
    );
    if (!qualified.success) {
      throw StateError(
        qualified.reason ?? 'Installed legion_cli qualification failed.',
      );
    }
    final runner = ManagedCommandRunner(
      openBus: openCommandBus,
      parentUnit: session.unit,
      lockPath: '/run/legion-control/operation.lock',
    );
    final clock = Stopwatch()..start();
    var lastActivity = clock.elapsedMicroseconds;
    final control = ControlDispatcher(
      execute: runner.start,
      cli: cli,
      sessionDirectory: Directory('${session.directory}/dart'),
      resources: linux,
    );
    dispatcher = control;
    peer = ControlPeerServer(
      path: '${session.directory}/control.sock',
      libraryPath: '${session.directory}/dart/lib/libsystemd.so.0',
      appPid: session.appPid,
      appUid: session.appUid,
      sessionAlive: () => !ended.isCompleted && alive(),
      onDisconnect: finish,
      onCall: (method, arguments) async {
        lastActivity = clock.elapsedMicroseconds;
        final reply = await control.call(method, arguments);
        final error = reply.errorName;
        if (error == null) return PeerReply(reply.values);
        return PeerReply.error(
          error.contains('.')
              ? error
              : error == 'InvalidArgs'
              ? 'org.freedesktop.DBus.Error.InvalidArgs'
              : '$controlInterface.Error.$error',
          reply.errorMessage,
        );
      },
    );
    peer.start();
    _checkLoadedFiles('${session.directory}/dart');
    stdout.writeln(
      'CONTROL_READY helper=$pid unit=${session.unit} '
      'address=unix:path=${session.directory}/control.sock '
      'bus=${manager.uniqueName} cli=${Uri.encodeComponent(cli)}',
    );
    await stdout.flush();
    lifetime = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!alive()) finish();
      if (control.active) lastActivity = clock.elapsedMicroseconds;
      final timeout = peer!.hasPeer ? session.idleSeconds : 10;
      if (clock.elapsedMicroseconds - lastActivity >= timeout * 1000000) {
        finish();
      }
    });
    await ended.future;
  } catch (error) {
    stdout.writeln('CONTROL_SETUP_ERROR $error');
    await stdout.flush();
    exitCode = 1;
  } finally {
    lifetime?.cancel();
    peer?.close();
    await dispatcher?.close();
    await manager?.close();
    for (final subscription in signals) {
      await subscription.cancel();
    }
  }
}

class _Session {
  const _Session(this.unit, this.appPid, this.appUid, this.idleSeconds);
  final String unit;
  final int appPid;
  final int appUid;
  final int idleSeconds;
  String get directory => '/run/${unit.substring(0, unit.length - 8)}';
}

_Session _readSession(List<String> arguments, LinuxResources linux) {
  if (arguments.length != 4 || !linux.isRoot) {
    throw const FormatException('The helper requires approved native startup.');
  }
  final unit = arguments[0];
  if (!RegExp(
    r'^legion-(portable-control|bootstrap-probe)-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.service$',
  ).hasMatch(unit)) {
    throw const FormatException('Invalid control service name.');
  }
  final session = _Session(
    unit,
    int.parse(arguments[1]),
    int.parse(arguments[2]),
    int.parse(arguments[3]),
  );
  if (session.appPid <= 1 ||
      session.appUid <= 0 ||
      session.idleSeconds <= 0 ||
      session.idleSeconds > 86400 ||
      linux.pinnedProcess(0) != session.appPid ||
      linux.pinnedProcess(3) <= 1 ||
      !linux.processAlive(0) ||
      !linux.processAlive(3) ||
      linux.inspectPath('/proc/${session.appPid}').uid != session.appUid ||
      !linux.processAlive(0) ||
      !linux.processAlive(3)) {
    throw const FormatException('The app identity or lifetime does not match.');
  }
  for (final (path, mode) in [
    (session.directory, 457), // 0711: systemd's session directory.
    ('${session.directory}/dart', 448), // 0700: native-staged runtime.
    ('${session.directory}/dart/lib', 448),
  ]) {
    final info = linux.inspectPath(path);
    if (info.uid != 0 || !info.directory || (info.mode & 511) != mode) {
      throw FileSystemException(
        'The control runtime directory is unsafe.',
        path,
      );
    }
  }
  return session;
}

/// Rejects library search-path fallback before announcing the control endpoint.
void _checkLoadedFiles(String runtime) {
  final mappings = File('/proc/self/maps')
      .readAsLinesSync()
      .where((line) => line.contains('/'))
      .map((line) => line.substring(line.indexOf('/')));
  if (mappings.isEmpty ||
      mappings.any((path) => !path.startsWith('$runtime/'))) {
    throw StateError('The helper loaded code outside its protected runtime.');
  }
}
