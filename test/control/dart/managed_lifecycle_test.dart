import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../control/dart/managed_command.dart';
import '../../../control/dart/systemd_bus.dart';

const _parent = 'legion-portable-control-test.service';

void main() {
  late File fixture;

  setUpAll(() async {
    final source = File(
      '${Directory.current.path}/test/control/dart/fake_systemd.cc',
    );
    final directory = await Directory.systemTemp.createTemp('fake-systemd-');
    addTearDown(() => directory.delete(recursive: true));
    fixture = File('${directory.path}/fake-systemd');
    final flags = await Process.run('pkg-config', [
      '--cflags',
      '--libs',
      'gio-2.0',
      'gio-unix-2.0',
    ]);
    expect(flags.exitCode, 0, reason: '${flags.stderr}');
    final arguments = (flags.stdout as String)
        .trim()
        .split(RegExp(r'\s+'))
        .where((value) => value.isNotEmpty)
        .toList();
    final compile = await Process.run('c++', [
      '-std=c++17',
      '-O0',
      source.path,
      '-o',
      fixture.path,
      ...arguments,
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');
    _Harness.fixture = fixture;
    final systemd = await Process.run('pkg-config', [
      '--variable=libdir',
      'libsystemd',
    ]);
    expect(systemd.exitCode, 0, reason: '${systemd.stderr}');
    _Harness.library = '${(systemd.stdout as String).trim()}/libsystemd.so.0';
  });

  test('success waits for EOF and an empty cgroup before unref', () async {
    final harness = await _Harness.start();
    addTearDown(harness.close);
    final operation = harness.runner().start('/bin/true', const [], 10);
    await harness.waitFor('STARTED');
    harness.command('finish');
    await harness.waitFor('STATUS_READ');
    harness.command('cgroup-empty');
    final result = await operation.result.timeout(const Duration(seconds: 5));
    expect(result.status, ManagedCommandStatus.success);
    expect(result.output, [111, 107]);
    await harness.waitFor('UNREF');
  });

  test('access denied releases the transient unit', () async {
    final harness = await _Harness.start(mode: 'reject');
    addTearDown(harness.close);
    final result = await harness
        .runner()
        .start('/bin/true', const [], 10)
        .result;
    expect(
      result.status,
      ManagedCommandStatus.unavailable,
      reason: result.error,
    );
    await harness.waitFor('UNREF');
  });

  test('cancellation stops the unit before reporting failure', () async {
    final harness = await _Harness.start();
    addTearDown(harness.close);
    final operation = harness.runner().start('/bin/true', const [], 10);
    await harness.waitFor('STARTED');
    operation.cancel();
    await harness.waitFor('STOPPED');
    expect(
      (await operation.result.timeout(const Duration(seconds: 5))).status,
      ManagedCommandStatus.commandFailed,
    );
    await harness.waitFor('UNREF');
  });

  test('losing the service name reports cleanup failure', () async {
    final harness = await _Harness.start();
    addTearDown(harness.close);
    final operation = harness.runner().start('/bin/true', const [], 10);
    await harness.waitFor('STARTED');
    harness.command('release-name');
    expect(
      (await operation.result.timeout(const Duration(seconds: 5))).status,
      ManagedCommandStatus.cleanupFailed,
    );
  });

  test('a held lock prevents a second StartTransientUnit', () async {
    final harness = await _Harness.start();
    addTearDown(harness.close);
    final lock = '${harness.directory.path}/operation.lock';
    final first = harness
        .runner(lockPath: lock)
        .start('/bin/true', const [], 10);
    await harness.waitFor('STARTED');
    final second = await harness
        .runner(lockPath: lock)
        .start('/bin/true', const [], 10)
        .result;
    expect(second.status, ManagedCommandStatus.busy);
    first.cancel();
    await first.result.timeout(const Duration(seconds: 5));
  });
}

class _Harness {
  _Harness._(
    this.directory,
    this.bus,
    this.daemon,
    this.service,
    this.lines,
    this.lineSubscription,
  );

  final Directory directory;
  final String bus;
  final Process daemon;
  final Process service;
  final StreamController<String> lines;
  final StreamSubscription<String> lineSubscription;
  final clients = <SystemdBusClient>[];
  final received = <String>[];

  static Future<_Harness> start({String mode = 'normal'}) async {
    final directory = await Directory.systemTemp.createTemp('managed-bus-');
    final config = File('${directory.path}/bus.conf')
      ..writeAsStringSync('''
<busconfig><type>session</type>
<listen>unix:path=${directory.path}/bus</listen><auth>EXTERNAL</auth>
<policy context="default"><allow send_destination="*" eavesdrop="true"/>
<allow receive_sender="*" eavesdrop="true"/><allow own="*"/></policy>
</busconfig>
''');
    final daemon = await Process.start('dbus-daemon', [
      '--config-file=${config.path}',
      '--nofork',
      '--print-address',
    ]);
    final address = await daemon.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    final service = await Process.start(fixture.path, [address, mode]);
    final lines = StreamController<String>.broadcast();
    final subscription = service.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(lines.add);
    final result = _Harness._(
      directory,
      address,
      daemon,
      service,
      lines,
      subscription,
    );
    lines.stream.listen(result.received.add);
    await result.waitFor('READY');
    return result;
  }

  static late File fixture;
  static late String library;

  ManagedCommandRunner runner({String? lockPath}) {
    final client = SystemdBusClient(libraryPath: library, address: bus);
    clients.add(client);
    return ManagedCommandRunner(
      openBus: () => client,
      parentUnit: _parent,
      lockPath: lockPath,
    );
  }

  Future<void> waitFor(String expected) async {
    if (received.contains(expected)) return;
    await lines.stream
        .firstWhere((line) => line == expected)
        .timeout(const Duration(seconds: 5));
  }

  void command(String command) {
    service.stdin.writeln(command);
  }

  Future<void> close() async {
    for (final client in clients) {
      await client.close();
    }
    await lineSubscription.cancel();
    await lines.close();
    service.kill();
    daemon.kill();
    await service.exitCode;
    await daemon.exitCode;
    await directory.delete(recursive: true);
  }
}
