import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dbus/dbus.dart';
import 'package:ffi/ffi.dart';

import 'linux_resources.dart';
import 'systemd_bus.dart';
import 'unix_descriptor.dart';

const _outputLimit = 64 * 1024;
const _managerPath = '/org/freedesktop/systemd1';
const _managerInterface = 'org.freedesktop.systemd1.Manager';

String _uuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

enum ManagedCommandStatus {
  success,
  busy,
  commandFailed,
  unavailable,
  timeout,
  outputLimit,
  cleanupFailed,
}

class ManagedCommandResult {
  const ManagedCommandResult({
    this.output = const <int>[],
    this.error = '',
    this.exitStatus = -1,
    this.status = ManagedCommandStatus.commandFailed,
  });

  final List<int> output;
  final String error;
  final int exitStatus;
  final ManagedCommandStatus status;
}

class ManagedCommandOperation {
  ManagedCommandOperation(this.result, this._cancel);

  final Future<ManagedCommandResult> result;
  final void Function() _cancel;
  void cancel() => _cancel();
}

/// Runs one transient, cgroup-contained systemd service at a time.
///
/// Each operation owns a connection so closing it releases systemd's AddRef.
/// systemd owns the child, its cgroup, and its termination.
class ManagedCommandRunner {
  ManagedCommandRunner({
    required this.openBus,
    required this.parentUnit,
    this.stateDirectory,
    this.lockPath,
  });

  final DBusClient Function() openBus;
  final String parentUnit;
  final String? stateDirectory;
  final String? lockPath;

  ManagedCommandOperation start(
    String executable,
    List<String> args,
    int runtimeSeconds,
  ) {
    final operation = _Operation(
      openBus(),
      parentUnit,
      stateDirectory,
      lockPath,
      executable,
      args,
      runtimeSeconds,
    );
    operation.begin();
    return ManagedCommandOperation(operation.future, operation.cancel);
  }
}

class _Operation {
  _Operation(
    this.bus,
    this.parent,
    this.stateDirectory,
    this.lockPath,
    this.executable,
    this.args,
    this.runtime,
  ) : unit = 'legion-control-op-${_uuid()}.service';

  final DBusClient bus;
  final String parent;
  final String? stateDirectory;
  final String? lockPath;
  final String executable;
  final List<String> args;
  final int runtime;
  final String unit;
  final _completion = Completer<ManagedCommandResult>();
  final output = <int>[];
  RawSocket? _output;
  int? _lock;
  String? _owner;
  String? _unitPath;
  StreamSubscription<DBusNameOwnerChangedEvent>? _ownerChanges;
  Timer? _pollTimer;
  Timer? _deadlineTimer;
  Timer? _runtimeTimer;
  Timer? _startupTimer;
  bool _polling = false;
  bool _statusReading = false;
  bool _eof = false;
  bool _cancelled = false;
  bool _stopping = false;
  bool _unreferenced = false;
  bool _started = false;
  bool _ending = false;
  ManagedCommandStatus _status = ManagedCommandStatus.commandFailed;
  int _exitStatus = -1;
  String _error = '';

  Future<ManagedCommandResult> get future => _completion.future;

  Future<void> begin() async {
    _deadlineTimer = Timer(Duration(seconds: runtime + 16), () {
      _end(
        ManagedCommandStatus.cleanupFailed,
        'command cleanup deadline exceeded',
      );
    });
    try {
      _owner = await _getOwner();
      if (_ending) return;
      if (_owner == null) {
        await _end(ManagedCommandStatus.unavailable, 'systemd unavailable');
        return;
      }
      _ownerChanges = bus.nameOwnerChanged.listen(
        (event) {
          if (event.name == 'org.freedesktop.systemd1' &&
              event.newOwner != _owner) {
            _end(ManagedCommandStatus.cleanupFailed, 'systemd owner changed');
          }
        },
        onError: (Object error) {
          _end(
            ManagedCommandStatus.cleanupFailed,
            'owner watch failed: $error',
          );
        },
        onDone: () {
          _end(ManagedCommandStatus.cleanupFailed, 'manager connection closed');
        },
      );
      if (!await _acquireLock()) return;
      await _startUnit();
    } catch (error) {
      _end(ManagedCommandStatus.cleanupFailed, '$error');
    }
  }

  Future<String?> _getOwner() async {
    try {
      final reply = await bus
          .callMethod(
            destination: 'org.freedesktop.DBus',
            path: DBusObjectPath('/org/freedesktop/DBus'),
            interface: 'org.freedesktop.DBus',
            name: 'GetNameOwner',
            values: [DBusString('org.freedesktop.systemd1')],
            replySignature: DBusSignature('s'),
          )
          .timeout(const Duration(seconds: 3));
      return reply.returnValues.single.asString();
    } catch (_) {
      return null;
    }
  }

  Future<bool> _acquireLock() async {
    if (lockPath == null || lockPath!.isEmpty) return true;
    final fd = _openLock(lockPath!);
    if (fd == null) {
      await _end(
        ManagedCommandStatus.unavailable,
        'operation lock is unavailable or has unsafe permissions',
      );
      return false;
    }
    _lock = fd;
    if (!_flock(fd, false)) {
      final busy = _lastErrno() == 11;
      await _end(
        busy ? ManagedCommandStatus.busy : ManagedCommandStatus.unavailable,
        busy
            ? 'another helper is running a control operation'
            : 'could not lock operation',
      );
      return false;
    }
    return true;
  }

  Future<void> _startUnit() async {
    if (_ending) return;
    final sockets = await _makeOutputSocket();
    if (_ending) {
      await sockets.$1.close();
      _close(sockets.$2);
      return;
    }
    _output = sockets.$1;
    var outputDescriptor = sockets.$2;
    void closeSentDescriptors() {
      if (outputDescriptor < 0) return;
      _close(outputDescriptor);
      outputDescriptor = -1;
    }

    try {
      final properties = <DBusValue>[
        _property('Type', DBusString('exec')),
        _property('CollectMode', DBusString('inactive-or-failed')),
        _property('KillMode', DBusString('control-group')),
        _property('Restart', DBusString('no')),
        _property(
          'StandardOutputFileDescriptor',
          LinuxDescriptorValue(outputDescriptor),
        ),
        _property(
          'StandardErrorFileDescriptor',
          LinuxDescriptorValue(outputDescriptor),
        ),
        _property('TimeoutStartUSec', DBusUint64(5000000)),
        _property('JobRunningTimeoutUSec', DBusUint64(5000000)),
        _property('RuntimeMaxUSec', DBusUint64(runtime * 1000000)),
        _property('TimeoutStopUSec', DBusUint64(2000000)),
        for (final name in [
          'AddRef',
          'SendSIGKILL',
          'NoNewPrivileges',
          'PrivateTmp',
          'ProtectHostname',
          'ProtectClock',
          'ProtectControlGroups',
          'ProtectKernelLogs',
          'ProtectKernelModules',
        ])
          _property(name, DBusBoolean(true)),
        _property('ProtectHome', DBusString('yes')),
        _property('ProtectSystem', DBusString('strict')),
        _property('WorkingDirectory', DBusString('/')),
        _property(
          'Environment',
          DBusArray.string([
            'PATH=${Platform.environment['PATH'] ?? '/usr/sbin:/usr/bin:/sbin:/bin'}',
            'LC_ALL=C',
            'HOME=/var/empty',
            'PYTHONNOUSERSITE=1',
            'PYTHONSAFEPATH=1',
          ]),
        ),
        _property(
          'ExecStartEx',
          DBusArray(DBusSignature('(sasas)'), [
            DBusStruct([
              DBusString(executable),
              DBusArray.string([executable, ...args]),
              DBusArray.string(['no-env-expand']),
            ]),
          ]),
        ),
        _property('BindsTo', DBusArray.string([parent])),
        _property('After', DBusArray.string([parent])),
        _property('JoinsNamespaceOf', DBusArray.string([parent])),
        _property('RestrictNamespaces', DBusUint64(0)),
        _property(
          'RestrictAddressFamilies',
          DBusStruct([
            DBusBoolean(true),
            DBusArray.string(['AF_UNIX']),
          ]),
        ),
        _property('SystemCallArchitectures', DBusArray.string(['native'])),
        _property('SystemCallErrorNumber', DBusInt32(1)),
        _property(
          'SystemCallFilter',
          DBusStruct([
            DBusBoolean(true),
            DBusArray.string(['@system-service']),
          ]),
        ),
      ];
      if (stateDirectory case final directory?) {
        properties.add(
          _property('StateDirectory', DBusArray.string([directory])),
        );
        properties.add(_property('StateDirectoryMode', DBusUint32(0x1c0)));
      }
      if (_lock case final fd?) {
        properties.add(
          _property('StandardInputFileDescriptor', LinuxDescriptorValue(fd)),
        );
      } else {
        properties.add(_property('StandardInput', DBusString('null')));
      }
      _readOutput();
      _startupTimer = Timer(const Duration(seconds: 5), () {
        if (!_ending && !_unreferenced) {
          _status = ManagedCommandStatus.timeout;
          _stop();
        }
      });
      await bus
          .callMethod(
            destination: _owner,
            path: DBusObjectPath(_managerPath),
            interface: _managerInterface,
            name: 'StartTransientUnit',
            values: [
              DBusString(unit),
              DBusString('fail'),
              DBusArray(DBusSignature('(sv)'), properties),
              DBusArray(DBusSignature('(sa(sv))'), []),
            ],
            replySignature: DBusSignature('o'),
          )
          .timeout(const Duration(seconds: 3));
      if (_ending) {
        return;
      }
      closeSentDescriptors();
      if (_ending) return;
      _started = true;
      _runtimeTimer = Timer(Duration(seconds: runtime + 5), () {
        if (!_ending && !_unreferenced) {
          _status = ManagedCommandStatus.timeout;
          _stop();
        }
      });
      final pathReply = await _callManager('GetUnit', [DBusString(unit)], 'o');
      if (_ending) return;
      _unitPath = pathReply.returnValues.single.asObjectPath().value;
      _pollTimer = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => _poll(),
      );
      if (_cancelled || _status == ManagedCommandStatus.timeout) _stop();
    } catch (error) {
      if (_ending) return;
      final rejected = !_started && _isExplicitStartRejection(error);
      final released = rejected && await _releaseRejected();
      closeSentDescriptors();
      await _end(
        released
            ? ManagedCommandStatus.unavailable
            : ManagedCommandStatus.cleanupFailed,
        '$error',
      );
    } finally {
      closeSentDescriptors();
    }
  }

  DBusStruct _property(String name, DBusValue value) =>
      DBusStruct([DBusString(name), DBusVariant(value)]);

  Future<DBusMethodSuccessResponse> _callManager(
    String name,
    List<DBusValue> values,
    String signature,
  ) {
    return bus
        .callMethod(
          destination: _owner,
          path: DBusObjectPath(_managerPath),
          interface: _managerInterface,
          name: name,
          values: values,
          replySignature: DBusSignature(signature),
        )
        .timeout(const Duration(seconds: 3));
  }

  Future<void> _readOutput() async {
    final socket = _output;
    if (socket == null) return;
    try {
      await for (final event in socket) {
        if (_ending) break;
        if (event == RawSocketEvent.read) {
          final chunk = socket.read();
          if (chunk == null) continue;
          if (output.length + chunk.length > _outputLimit) {
            output.addAll(chunk.take(_outputLimit - output.length));
            _status = ManagedCommandStatus.outputLimit;
            _stop();
            continue;
          }
          output.addAll(chunk);
        } else if (event == RawSocketEvent.readClosed ||
            event == RawSocketEvent.closed) {
          _eof = true;
          break;
        }
      }
      _eof = true;
      if (_unreferenced && !_ending) _end(_status);
    } catch (error) {
      if (!_ending) _end(ManagedCommandStatus.cleanupFailed, '$error');
    }
  }

  Future<void> _poll() async {
    if (_ending || _unitPath == null || _polling) return;
    _polling = true;
    try {
      final unitReply = await bus
          .callMethod(
            destination: _owner,
            path: DBusObjectPath(_unitPath!),
            interface: 'org.freedesktop.DBus.Properties',
            name: 'GetAll',
            values: [DBusString('org.freedesktop.systemd1.Unit')],
            replySignature: DBusSignature('a{sv}'),
          )
          .timeout(const Duration(seconds: 3));
      if (_ending) return;
      final unitProps = unitReply.returnValues.single.asDict();
      final state = _dictValue(
        unitProps,
        'ActiveState',
      )?.asVariant().asString();
      final jobValue = _dictValue(unitProps, 'Job');
      final job = jobValue?.asVariant().asStruct()[0].asUint32();
      if (state == null || job == null) {
        throw StateError('incomplete command unit state');
      }
      if (state != 'inactive') _startupTimer?.cancel();
      if (job == 0 && (state == 'inactive' || state == 'failed')) {
        _startupTimer?.cancel();
        await _statusAndRelease();
      }
    } catch (error) {
      _end(ManagedCommandStatus.cleanupFailed, '$error');
    } finally {
      _polling = false;
    }
  }

  Future<void> _statusAndRelease() async {
    if (_ending || _unreferenced || _statusReading) return;
    _statusReading = true;
    try {
      final reply = await bus
          .callMethod(
            destination: _owner,
            path: DBusObjectPath(_unitPath!),
            interface: 'org.freedesktop.DBus.Properties',
            name: 'GetAll',
            values: [DBusString('org.freedesktop.systemd1.Service')],
            replySignature: DBusSignature('a{sv}'),
          )
          .timeout(const Duration(seconds: 3));
      if (_ending) return;
      final props = reply.returnValues.single.asDict();
      final code = _dictValue(props, 'ExecMainCode')?.asVariant().asInt32();
      final status = _dictValue(props, 'ExecMainStatus')?.asVariant().asInt32();
      final serviceResult = _dictValue(props, 'Result')?.asVariant().asString();
      final cgroup = _dictValue(props, 'ControlGroup')?.asVariant().asString();
      if (code == null ||
          status == null ||
          serviceResult == null ||
          cgroup == null) {
        throw StateError('incomplete command status');
      }
      if (cgroup.isNotEmpty) return;
      _exitStatus = code == 1 ? status : -1;
      if (serviceResult == 'timeout' &&
          _status != ManagedCommandStatus.outputLimit) {
        _status = ManagedCommandStatus.timeout;
      } else if (_status != ManagedCommandStatus.timeout &&
          _status != ManagedCommandStatus.outputLimit) {
        _status =
            !_cancelled &&
                code == 1 &&
                status == 0 &&
                serviceResult == 'success'
            ? ManagedCommandStatus.success
            : ManagedCommandStatus.commandFailed;
      }
      await _callManager('UnrefUnit', [DBusString(unit)], '');
      if (_ending) return;
      _unreferenced = true;
      if (_eof) {
        _end(_status);
      } else {
        Timer(const Duration(seconds: 2), () {
          if (!_ending && _unreferenced) {
            _end(
              ManagedCommandStatus.cleanupFailed,
              'command output drain deadline exceeded',
            );
          }
        });
      }
    } catch (error) {
      _end(ManagedCommandStatus.cleanupFailed, '$error');
    } finally {
      _statusReading = false;
    }
  }

  void cancel() {
    _cancelled = true;
    if (_started && !_stopping) _stop();
  }

  void _stop() {
    if (_stopping || _ending) return;
    if (!_started) {
      _cancelled = true;
      return;
    }
    _stopping = true;
    unawaited(() async {
      try {
        await _callManager('StopUnit', [
          DBusString(unit),
          DBusString('replace'),
        ], 'o');
      } catch (error) {
        _end(
          ManagedCommandStatus.cleanupFailed,
          'could not confirm stop request: $error',
        );
      }
    }());
  }

  Future<bool> _releaseRejected() async {
    try {
      await _callManager('UnrefUnit', [DBusString(unit)], '');
      return true;
    } on DBusMethodResponseException catch (error) {
      return error.errorName == 'org.freedesktop.systemd1.NoSuchUnit' ||
          error.errorName == 'org.freedesktop.systemd1.NotReferenced';
    } catch (_) {}
    return false;
  }

  bool _isExplicitStartRejection(Object error) {
    if (error is! DBusMethodResponseException) return false;
    final name = error.errorName;
    return name.startsWith('org.freedesktop.systemd1.') ||
        name == 'org.freedesktop.DBus.Error.InvalidArgs' ||
        name == 'org.freedesktop.DBus.Error.AccessDenied' ||
        name == 'org.freedesktop.DBus.Error.PropertyReadOnly' ||
        name == 'org.freedesktop.DBus.Error.UnknownProperty';
  }

  Future<bool> _end(ManagedCommandStatus status, [String error = '']) async {
    if (_ending) return false;
    _ending = true;
    _status = status;
    _error = error;
    _pollTimer?.cancel();
    _deadlineTimer?.cancel();
    _runtimeTimer?.cancel();
    _startupTimer?.cancel();
    await _ownerChanges?.cancel();
    await _output?.close();
    await bus.close();
    if (_lock case final fd?) {
      _close(fd);
      _lock = null;
    }
    if (!_completion.isCompleted) {
      _completion.complete(
        ManagedCommandResult(
          output: List.unmodifiable(output),
          error: _error,
          exitStatus: _exitStatus,
          status: _status,
        ),
      );
    }
    return true;
  }
}

DBusValue? _dictValue(Map<DBusValue, DBusValue> dict, String key) =>
    dict[DBusString(key)];

Future<(RawSocket, int)> _makeOutputSocket() async {
  final pair = calloc<Int32>(2);
  final socketPair = _libc
      .lookupFunction<
        Int32 Function(Int32, Int32, Int32, Pointer<Int32>),
        int Function(int, int, int, Pointer<Int32>)
      >('socketpair');
  if (socketPair(1, 1 | 0x80000, 0, pair) != 0) {
    calloc.free(pair);
    throw const SocketException('Could not create command output sockets.');
  }
  final read = pair[0];
  final write = pair[1];
  calloc.free(pair);
  try {
    final handle = await resourceHandleForDescriptor(read);
    return (handle.toRawSocket(), write);
  } catch (_) {
    _close(write);
    rethrow;
  } finally {
    _close(read);
  }
}

final _libc = DynamicLibrary.process();
final _openNative = _libc
    .lookupFunction<
      Int32 Function(Pointer<Utf8>, Int32, Int32),
      int Function(Pointer<Utf8>, int, int)
    >('open');
final _flockNative = _libc
    .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
      'flock',
    );
final _closeNative = _libc
    .lookupFunction<Int32 Function(Int32), int Function(int)>('close');
final _statxNative = _libc
    .lookupFunction<
      Int32 Function(Int32, Pointer<Utf8>, Int32, Uint32, Pointer<Uint8>),
      int Function(int, Pointer<Utf8>, int, int, Pointer<Uint8>)
    >('statx');
final _errnoLocation = _libc
    .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
      '__errno_location',
    );

int? _openLock(String path) {
  final text = path.toNativeUtf8();
  final fd = _openNative(text, 0x42 | 0x20000 | 0x80000, 0x180);
  calloc.free(text);
  if (fd < 0) return null;
  final info = LinuxResources().inspectDescriptor(fd);
  final statx = calloc<Uint8>(256);
  final empty = ''.toNativeUtf8();
  final statxResult = _statxNative(fd, empty, 0x1000, 0x200, statx);
  calloc.free(empty);
  final size = statxResult == 0
      ? ByteData.sublistView(statx.asTypedList(256)).getUint64(40, Endian.host)
      : -1;
  calloc.free(statx);
  final valid =
      statxResult == 0 &&
      info.regularFile &&
      info.uid == _geteuid() &&
      (info.mode & 0x1ff) == 0x180 &&
      info.links == 1 &&
      size == 0;
  if (!valid) {
    _close(fd);
    return null;
  }
  return fd;
}

bool _flock(int fd, bool unlock) => _flockNative(fd, unlock ? 8 : 2 | 4) == 0;
void _close(int fd) => _closeNative(fd);
int _lastErrno() => _errnoLocation().value;
int _geteuid() =>
    _libc.lookupFunction<Uint32 Function(), int Function()>('geteuid')();
