import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:legion_frontend/core/models/control_selectors.dart';
import 'package:legion_frontend/core/services/legion_control_client.dart';

const _interface = 'io.github.prnice.LegionControl1';
const _objectPath = '/io/github/prnice/LegionControl1';
const _maxOutputBytes = 64 * 1024;
const _operationTimeout = Duration(seconds: 4);

class _Handshake {
  const _Handshake({
    required this.address,
    required this.fixture,
    required this.directory,
  });

  final String address;
  final String fixture;
  final String directory;

  factory _Handshake.parse(String line) {
    final value = jsonDecode(line);
    if (value is! Map<String, dynamic> ||
        value.keys.toSet().difference({
          'address',
          'fixture',
          'directory',
          'authorization',
        }).isNotEmpty ||
        value['address'] is! String ||
        value['fixture'] is! String ||
        value['directory'] is! String ||
        value['authorization'] != 'FAKE') {
      throw const FormatException('invalid private-peer handshake');
    }
    return _Handshake(
      address: value['address'] as String,
      fixture: value['fixture'] as String,
      directory: value['directory'] as String,
    );
  }
}

// Observe the authentication exchange directly so a rejected peer is distinct
// from a method call that never receives a reply.
class _PeerSocket {
  _PeerSocket(this.socket) {
    socket.listen(
      (bytes) {
        if (_buffer.length + bytes.length > _maxOutputBytes) {
          _error = StateError('private peer exceeded the input limit');
          socket.destroy();
          _close();
          return;
        }
        if (_afterBegin && bytes.isNotEmpty) _receivedAfterBegin = true;
        _buffer.addAll(bytes);
        _notify();
      },
      onError: (Object error, StackTrace stackTrace) {
        _error = error;
        _close();
      },
      onDone: _close,
    );
  }

  final Socket socket;
  final ListQueue<int> _buffer = ListQueue<int>();
  final Completer<void> _closed = Completer<void>();
  Completer<void>? _changed;
  Object? _error;
  String? authResponse;
  bool _isClosed = false;
  bool _afterBegin = false;
  bool _receivedAfterBegin = false;

  Future<void> get closed => _closed.future.then((_) {
    if (_error != null) throw _error!;
  });
  bool get receivedAfterBegin => _receivedAfterBegin;

  void _close() {
    _isClosed = true;
    _notify();
    if (!_closed.isCompleted) _closed.complete();
  }

  void _notify() {
    final changed = _changed;
    _changed = null;
    if (changed != null && !changed.isCompleted) changed.complete();
  }

  Future<String?> readLine() async {
    while (true) {
      final newline = _buffer.toList().indexOf(10);
      if (newline >= 0) {
        final bytes = List<int>.generate(newline, (_) => _buffer.removeFirst());
        _buffer.removeFirst();
        if (bytes.isNotEmpty && bytes.last == 13) bytes.removeLast();
        return utf8.decode(bytes);
      }
      if (_isClosed) {
        if (_error != null) throw _error!;
        return null;
      }
      _changed = Completer<void>();
      await _changed!.future;
    }
  }

  void beginMessages() {
    _afterBegin = true;
    socket.add(utf8.encode('BEGIN\r\n'));
  }
}

class _ProbeProcess {
  _ProbeProcess(this.process) {
    process.stdout
        .transform(utf8.decoder)
        .listen(
          (text) => _consume(text, isError: false),
          onError: _streamError,
          onDone: () {
            _checkMissingHandshake();
            _streamDone();
          },
        );
    process.stderr
        .transform(utf8.decoder)
        .listen(
          (text) => _consume(text, isError: true),
          onError: _streamError,
          onDone: _streamDone,
        );
    process.exitCode.then((code) {
      _exitCode = code;
      _checkMissingHandshake();
    });
  }

  final Process process;
  final Completer<_Handshake> _handshake = Completer<_Handshake>();
  final StringBuffer _stderr = StringBuffer();
  String _partialLine = '';
  final Completer<void> _streamsDone = Completer<void>();
  int _streamsRemaining = 2;
  int _stdoutBytes = 0;
  int _stderrBytes = 0;
  int? _exitCode;
  Object? _outputError;

  String get stderrText => _stderr.toString();

  Future<_Handshake> get handshake => _handshake.future.timeout(
    const Duration(seconds: 5),
    onTimeout: () =>
        throw TimeoutException('native helper did not publish its address'),
  );

  void _consume(String text, {required bool isError}) {
    final byteCount = utf8.encode(text).length;
    if (isError) {
      final remaining = _maxOutputBytes - _stderrBytes;
      if (remaining > 0) {
        _stderr.write(_utf8Prefix(text, remaining));
      }
      _stderrBytes += byteCount;
      if (_stderrBytes > _maxOutputBytes) {
        _outputError ??= StateError(
          'native helper stderr exceeded the output limit',
        );
      }
      return;
    }

    _stdoutBytes += byteCount;
    if (_stdoutBytes > _maxOutputBytes) {
      _recordOutputError(
        StateError('native helper stdout exceeded the output limit'),
      );
      return;
    }
    final lines = ('$_partialLine$text').split('\n');
    _partialLine = lines.removeLast();
    for (final line in lines) {
      if (line.length > 8192) {
        _recordOutputError(const FormatException('native line exceeded 8 KiB'));
      } else if (!_handshake.isCompleted) {
        try {
          _handshake.complete(_Handshake.parse(line));
        } on Object catch (error, stackTrace) {
          _outputError ??= error;
          _handshake.completeError(error, stackTrace);
        }
      } else if (line.isNotEmpty) {
        _recordOutputError(
          const FormatException('native helper printed extra stdout'),
        );
      }
    }
  }

  void _fail(Object error, [StackTrace? stackTrace]) {
    if (!_handshake.isCompleted) {
      _handshake.completeError(error, stackTrace);
    }
  }

  void _streamError(Object error, [StackTrace? stackTrace]) {
    _outputError ??= error;
    _fail(error, stackTrace);
  }

  String _utf8Prefix(String text, int maxBytes) {
    final prefix = StringBuffer();
    var usedBytes = 0;
    for (final rune in text.runes) {
      final runeBytes = rune <= 0x7f
          ? 1
          : rune <= 0x7ff
          ? 2
          : rune <= 0xffff
          ? 3
          : 4;
      if (usedBytes + runeBytes > maxBytes) break;
      prefix.writeCharCode(rune);
      usedBytes += runeBytes;
    }
    return prefix.toString();
  }

  void _checkMissingHandshake() {
    // Process exit can arrive before the last pipe data has been delivered.
    if (_streamsRemaining != 0 || _exitCode == null) return;
    if (_partialLine.isNotEmpty) {
      _recordOutputError(
        const FormatException(
          'native helper ended with an unterminated stdout line',
        ),
      );
    }
    if (_exitCode != null && !_handshake.isCompleted) {
      _fail(
        StateError(
          'native helper exited with $_exitCode: ${stderrText.trim()}',
        ),
      );
    }
  }

  void _recordOutputError(Object error) {
    _outputError ??= error;
    _fail(error);
  }

  void _streamDone() {
    _streamsRemaining--;
    if (_streamsRemaining == 0 && !_streamsDone.isCompleted) {
      _checkMissingHandshake();
      _streamsDone.complete();
    }
  }

  Future<int> waitForExit({Duration timeout = _operationTimeout}) async {
    final code = await process.exitCode.timeout(timeout);
    await _streamsDone.future.timeout(timeout);
    if (_outputError != null) {
      throw StateError('native helper output failed: $_outputError');
    }
    return code;
  }

  Future<void> stop() async {
    if (_exitCode == null) {
      process.kill(ProcessSignal.sigterm);
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode.timeout(_operationTimeout);
      }
    }
  }
}

class _PeerTransport implements LegionControlTransport {
  _PeerTransport(this.client);

  final DBusClient client;
  bool _closed = false;

  @override
  Future<void> authorize() => _call('Authorize', const []);

  @override
  Future<void> call(String method, List<Object> arguments) =>
      _call(method, arguments);

  Future<void> _call(String method, List<Object> arguments) async {
    if (_closed) throw StateError('private peer is closed');
    await client
        .callMethod(
          path: DBusObjectPath(_objectPath),
          interface: _interface,
          name: method,
          values: arguments.map(_dbusValue),
          replySignature: DBusSignature.empty,
        )
        .timeout(_operationTimeout);
  }

  DBusValue _dbusValue(Object value) => switch (value) {
    String() => DBusString(value),
    bool() => DBusBoolean(value),
    int() => DBusUint32(value),
    List<int>() => DBusArray.byte(value),
    _ => throw ArgumentError.value(value, 'value', 'unsupported D-Bus value'),
  };

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await client.close();
  }
}

Future<_ProbeProcess> _launch(
  String helper, {
  int? clientPid,
  int startupTimeoutMs = 8000,
  bool cancelFakeAuthorization = false,
}) async {
  final process = await Process.start(helper, [
    if (clientPid != null) ...['--client-pid', '$clientPid'],
    '--startup-timeout-ms',
    '$startupTimeoutMs',
    if (cancelFakeAuthorization) '--fake-auth-cancel',
  ]);
  final probe = _ProbeProcess(process);
  try {
    await probe.handshake;
    return probe;
  } on Object {
    await probe.stop();
    rethrow;
  }
}

DBusClient _peerClient(String address) =>
    DBusClient(DBusAddress(address), messageBus: false);

Future<void> _expectError(
  Future<Object?> Function() call,
  String errorSuffix,
) async {
  try {
    await call();
  } on DBusMethodResponseException catch (error) {
    if (!error.errorName.endsWith(errorSuffix)) {
      throw StateError('expected $errorSuffix, got ${error.errorName}');
    }
    return;
  }
  throw StateError('expected D-Bus error ending in $errorSuffix');
}

Future<_PeerSocket> _authenticatePrivatePeer(String address) async {
  final parsedAddress = DBusAddress(address);
  final socketPath = parsedAddress.properties['path'];
  if (parsedAddress.transport != 'unix' || socketPath == null) {
    throw StateError('probe published a non-Unix private address');
  }
  final uidMatch = RegExp(
    r'^Uid:\s+(\d+)',
    multiLine: true,
  ).firstMatch(await File('/proc/self/status').readAsString());
  if (uidMatch == null) throw StateError('could not read client UID');
  final uidHex = utf8
      .encode(uidMatch.group(1)!)
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();

  final socket = await Socket.connect(
    InternetAddress(socketPath, type: InternetAddressType.unix),
    0,
  ).timeout(const Duration(seconds: 2));
  final peer = _PeerSocket(socket);
  try {
    socket.add([0, ...utf8.encode('AUTH\r\n')]);
    final greeting = await peer.readLine().timeout(const Duration(seconds: 2));
    if (greeting == null) {
      throw StateError('peer closed before advertising D-Bus auth mechanisms');
    }
    final normalizedGreeting = greeting.replaceFirst('\u0000', '');
    if (!normalizedGreeting.startsWith('REJECTED')) {
      throw StateError('unexpected D-Bus auth greeting: $normalizedGreeting');
    }

    socket.add(utf8.encode('AUTH EXTERNAL $uidHex\r\n'));
    final response = await peer.readLine().timeout(const Duration(seconds: 2));
    if (response == null) {
      peer.authResponse = null;
      return peer;
    }
    final normalizedResponse = response.replaceFirst('\u0000', '');
    peer.authResponse = normalizedResponse;
    if (normalizedResponse.startsWith('REJECTED')) return peer;
    if (!normalizedResponse.startsWith('OK ')) {
      throw StateError(
        'unexpected D-Bus EXTERNAL response: $normalizedResponse',
      );
    }
    socket.add(utf8.encode('NEGOTIATE_UNIX_FD\r\n'));
    final negotiation = await peer.readLine().timeout(
      const Duration(seconds: 2),
    );
    if (negotiation == null ||
        !(negotiation.startsWith('AGREE_UNIX_FD') ||
            negotiation.startsWith('ERROR'))) {
      throw StateError('unexpected D-Bus FD negotiation: $negotiation');
    }
    return peer;
  } on Object {
    socket.destroy();
    rethrow;
  }
}

Future<void> _authenticateAndRequireRejection(String address) async {
  final peer = await _authenticatePrivatePeer(address);
  try {
    if (peer.authResponse?.startsWith('OK ') ?? false) {
      throw StateError('wrong-PID peer authenticated successfully');
    }
    final response = peer.authResponse;
    if (response != null && !response.startsWith('REJECTED')) {
      throw StateError('wrong-PID peer got unexpected response: $response');
    }
  } finally {
    peer.socket.destroy();
  }
}

Future<void> _authenticateAndRequireClose(String address) async {
  final peer = await _authenticatePrivatePeer(address);
  try {
    if (!(peer.authResponse?.startsWith('OK ') ?? false)) {
      throw StateError(
        'second same-PID peer did not authenticate via EXTERNAL',
      );
    }
    peer.beginMessages();
    await peer.closed.timeout(const Duration(seconds: 2));
    if (peer.receivedAfterBegin) {
      throw StateError('server sent D-Bus data to the rejected second client');
    }
  } finally {
    peer.socket.destroy();
  }
}

Future<void> _expectRemoved(_Handshake handshake) async {
  final socketPath = DBusAddress(handshake.address).properties['path'];
  if (socketPath == null) {
    throw StateError('private peer address did not include its socket path');
  }
  if (await Directory(handshake.directory).exists() ||
      await File(handshake.fixture).exists() ||
      await FileSystemEntity.type(socketPath, followLinks: false) !=
          FileSystemEntityType.notFound) {
    throw StateError('probe socket, fixture, or temporary directory remains');
  }
}

Future<void> _closeProcessInput(Process process) async {
  try {
    await process.stdin.close().timeout(_operationTimeout);
  } on SocketException {
    // The child can exit while its input pipe is closing.
  } on StateError {
    // The input pipe can already be closed by a child that exited early.
  }
}

Future<int> _waitForChild(Process process) async {
  try {
    return await process.exitCode.timeout(_operationTimeout);
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    return process.exitCode.timeout(_operationTimeout);
  }
}

Future<void> _stopChild(Process process) async {
  try {
    await _closeProcessInput(process);
  } finally {
    await _waitForChild(process);
  }
}

Future<void> _exerciseControl(String helper) async {
  final probe = await _launch(helper);
  DBusClient? peer;
  var completed = false;
  try {
    final handshake = await probe.handshake;
    final client = _peerClient(handshake.address);
    peer = client;
    final raw = peer;
    final fixture = File(handshake.fixture);
    if (await fixture.readAsString() != 'disabled\n') {
      throw StateError('synthetic battery fixture did not start disabled');
    }

    await _expectError(() async {
      await raw
          .callMethod(
            path: DBusObjectPath(_objectPath),
            interface: _interface,
            name: 'SetToggle',
            values: [DBusString('battery-conservation'), DBusBoolean(true)],
            replySignature: DBusSignature.empty,
          )
          .timeout(_operationTimeout);
      return null;
    }, 'AccessDenied');
    if (await fixture.readAsString() != 'disabled\n') {
      throw StateError('unauthorized call changed synthetic battery state');
    }

    final control = LegionControlClient(transport: _PeerTransport(client));
    await control.setToggle(ControlToggle.batteryConservation, true);
    final readback = await fixture.readAsString();
    if (readback != 'enabled\n') {
      throw StateError('synthetic battery readback was $readback');
    }

    await _expectError(() async {
      await raw
          .callMethod(
            path: DBusObjectPath(_objectPath),
            interface: _interface,
            name: 'ApplyCustomConservation',
            values: [DBusUint32(101), DBusUint32(100)],
            replySignature: DBusSignature.empty,
          )
          .timeout(_operationTimeout);
      return null;
    }, 'InvalidArgs');
    if (await fixture.readAsString() != 'enabled\n') {
      throw StateError(
        'invalid native request changed synthetic battery state',
      );
    }

    await _expectError(() async {
      await raw
          .callMethod(
            path: DBusObjectPath(_objectPath),
            interface: _interface,
            name: 'SetFeature',
            values: [DBusString('OverdriveFeature'), DBusString('1')],
            replySignature: DBusSignature.empty,
          )
          .timeout(_operationTimeout);
      return null;
    }, 'Error.CommandFailed');
    if (await fixture.readAsString() != 'enabled\n') {
      throw StateError(
        'unsupported fake-backend command changed battery state',
      );
    }

    await _authenticateAndRequireClose(handshake.address);

    // Refusing a second peer must preserve the first peer's authorized session.
    await control.setToggle(ControlToggle.batteryConservation, false);
    if (await fixture.readAsString() != 'disabled\n') {
      throw StateError('the original client could not restore synthetic state');
    }

    await peer.close().timeout(_operationTimeout);
    peer = null;
    final exitCode = await probe.waitForExit();
    if (exitCode != 0) {
      throw StateError(
        'clean disconnect exited $exitCode: ${probe.stderrText}',
      );
    }
    await _expectRemoved(handshake);
    completed = true;
  } finally {
    try {
      if (peer != null) await peer.close().timeout(_operationTimeout);
    } finally {
      if (!completed) await probe.stop();
    }
  }
}

Future<void> _exerciseFakeAuthorizationCancellation(String helper) async {
  final probe = await _launch(helper, cancelFakeAuthorization: true);
  DBusClient? peer;
  var completed = false;
  try {
    final handshake = await probe.handshake;
    final client = _peerClient(handshake.address);
    peer = client;
    if (await File(handshake.fixture).readAsString() != 'disabled\n') {
      throw StateError('synthetic battery fixture did not start disabled');
    }
    await _expectError(() async {
      await _PeerTransport(client).authorize();
      return null;
    }, 'AccessDenied');
    await _expectError(() async {
      await _PeerTransport(
        client,
      ).call('SetToggle', ['battery-conservation', true]);
      return null;
    }, 'AccessDenied');
    if (await File(handshake.fixture).readAsString() != 'disabled\n') {
      throw StateError(
        'cancelled authorization changed synthetic battery state',
      );
    }
    await peer.close().timeout(_operationTimeout);
    peer = null;
    final exitCode = await probe.waitForExit();
    if (exitCode != 0) {
      throw StateError('fake authorization cancellation exited $exitCode');
    }
    await _expectRemoved(handshake);
    completed = true;
  } finally {
    try {
      if (peer != null) await peer.close().timeout(_operationTimeout);
    } finally {
      if (!completed) await probe.stop();
    }
  }
}

Future<void> _exerciseRejectedPeer(String helper) async {
  final holdClient = await Process.start(Platform.resolvedExecutable, [
    Platform.script.toFilePath(),
    '--hold-client',
  ]);
  holdClient.stdout.listen((_) {});
  holdClient.stderr.listen((_) {});
  _ProbeProcess? probe;
  var completed = false;
  try {
    probe = await _launch(
      helper,
      clientPid: holdClient.pid,
      // The server timeout exceeds both two-second auth reads, so a stalled
      // handshake cannot pass by being closed by the startup timer.
      startupTimeoutMs: 5000,
    );
    final handshake = await probe.handshake;
    await _authenticateAndRequireRejection(handshake.address);
    await _closeProcessInput(holdClient);
    await _waitForChild(holdClient);
    final exitCode = await probe.waitForExit(
      timeout: const Duration(seconds: 6),
    );
    if (exitCode != 5 || !probe.stderrText.contains('timed out')) {
      throw StateError('wrong-PID peer was not rejected: $exitCode');
    }
    await _expectRemoved(handshake);
    completed = true;
  } finally {
    try {
      await _stopChild(holdClient);
    } finally {
      if (!completed) await probe?.stop();
    }
  }
}

Future<void> _exerciseStartupTimeout(String helper) async {
  final probe = await _launch(helper, startupTimeoutMs: 900);
  try {
    final handshake = await probe.handshake;
    final exitCode = await probe.waitForExit(
      timeout: const Duration(seconds: 4),
    );
    if (exitCode != 5 || !probe.stderrText.contains('timed out')) {
      throw StateError('unconnected helper did not time out: $exitCode');
    }
    await _expectRemoved(handshake);
  } finally {
    await probe.stop();
  }
}

Future<void> _exerciseClientCrash(String helper) async {
  final child = await Process.start(Platform.resolvedExecutable, [
    Platform.script.toFilePath(),
    '--crash-client',
  ]);
  child.stdout.listen((_) {});
  child.stderr.listen((_) {});
  _ProbeProcess? probe;
  var completed = false;
  try {
    probe = await _launch(helper, clientPid: child.pid);
    final handshake = await probe.handshake;
    child.stdin.writeln(handshake.address);
    await _closeProcessInput(child);
    final childExit = await child.exitCode.timeout(_operationTimeout);
    if (childExit != 0) {
      throw StateError('crash client exited $childExit');
    }
    final helperExit = await probe.waitForExit();
    if (helperExit != 0) {
      throw StateError(
        'helper did not clean up after client exit: $helperExit',
      );
    }
    await _expectRemoved(handshake);
    completed = true;
  } finally {
    try {
      await _stopChild(child);
    } finally {
      if (!completed) await probe?.stop();
    }
  }
}

Future<void> _exerciseStartupCancellation(String helper) async {
  final probe = await _launch(helper);
  try {
    final handshake = await probe.handshake;
    await probe.stop();
    if (await probe.waitForExit() != 0) {
      throw StateError('helper did not exit cleanly on startup cancellation');
    }
    await _expectRemoved(handshake);
  } finally {
    await probe.stop();
  }
}

Future<void> _crashClient() async {
  final address = await stdin.transform(utf8.decoder).join();
  final client = _peerClient(address.trim());
  await _PeerTransport(client).authorize();
  // Exit without closing the D-Bus client to exercise peer-disconnect cleanup.
  exit(0);
}

Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && arguments.single == '--crash-client') {
    await _crashClient();
    return;
  }
  if (arguments.length == 1 && arguments.single == '--hold-client') {
    await stdin.drain<void>();
    return;
  }

  String? helper;
  for (var index = 0; index < arguments.length; index++) {
    if (arguments[index] == '--helper' && index + 1 < arguments.length) {
      helper = arguments[++index];
    } else {
      stderr.writeln(
        'usage: dart run tool/probe_portable_control.dart --helper <portable_control_probe>',
      );
      exitCode = 2;
      return;
    }
  }
  helper ??= Platform.environment['PORTABLE_CONTROL_PROBE'];
  if (helper == null || helper.isEmpty) {
    stderr.writeln('pass --helper <portable_control_probe>');
    exitCode = 2;
    return;
  }

  try {
    await _exerciseControl(helper);
    stdout.writeln(
      'PASS private peer, FAKE authorization, C++ validation, synthetic write/readback, one client, and disconnect',
    );
    await _exerciseFakeAuthorizationCancellation(helper);
    stdout.writeln('PASS fake authorization cancellation');
    await _exerciseRejectedPeer(helper);
    stdout.writeln('PASS wrong-PID peer rejection');
    await _exerciseStartupTimeout(helper);
    stdout.writeln('PASS startup timeout');
    await _exerciseStartupCancellation(helper);
    stdout.writeln('PASS startup cancellation cleanup');
    await _exerciseClientCrash(helper);
    stdout.writeln('PASS cleanup after client process exit');
    stdout.writeln(
      'Verified with a fixed synthetic backend. Real Polkit, hardware access, and backend descendant cleanup remain unverified.',
    );
  } on Object catch (error, stackTrace) {
    stderr.writeln('FAIL $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
  }
}
