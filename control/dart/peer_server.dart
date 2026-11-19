import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

const controlInterface = 'io.github.prnice.LegionControl1';
const controlObjectPath = '/io/github/prnice/LegionControl1';

const _methods = <String, (String, String)>{
  'GetCapabilities': ('', 'uas'),
  'Authorize': ('', ''),
  'SetFeature': ('ss', ''),
  'SetToggle': ('sb', ''),
  'SetGraphicsMode': ('s', ''),
  'ApplyFanPreset': ('s', ''),
  'ApplyCurrentFanPreset': ('', ''),
  'ApplyCustomConservation': ('uu', ''),
  'ApplyFanCurve': ('ay', ''),
  'SetBootLogo': ('ay', ''),
  'RestoreBootLogo': ('', ''),
  'SetServiceEnabled': ('sb', ''),
  'RequestGraphicsModeAtBoot': ('s', 's'),
  'CancelGraphicsModeAtBoot': ('', 's'),
  'GetGraphicsBootRequest': ('', 's'),
};

String _introspectionXml() {
  final xml = StringBuffer('<node><interface name="$controlInterface">');
  for (final entry in _methods.entries) {
    xml.write('<method name="${entry.key}">');
    for (final (signature, direction) in [
      (entry.value.$1, 'in'),
      (entry.value.$2, 'out'),
    ]) {
      for (var index = 0; index < signature.length; index++) {
        final type = signature[index] == 'a'
            ? 'a${signature[++index]}'
            : signature[index];
        xml.write('<arg type="$type" direction="$direction"/>');
      }
    }
    xml.write('</method>');
  }
  return '$xml</interface></node>';
}

final class _BusId extends Union {
  @Array(2)
  external Array<Uint64> words;
}

final class _BusError extends Struct {
  external Pointer<Utf8> name;
  external Pointer<Utf8> message;
  @Int32()
  external int needFree;
}

typedef _MessageCallback = Int32 Function(
  Pointer<Void>,
  Pointer<Void>,
  Pointer<_BusError>,
);

class PeerReply {
  const PeerReply([this.values = const []])
    : errorName = null,
      errorMessage = null;

  const PeerReply.error(this.errorName, this.errorMessage) : values = const [];

  final List<Object> values;
  final String? errorName;
  final String? errorMessage;
}

/// Uses libsystemd's supported D-Bus implementation for the app's private socket.
///
/// All library processing and callbacks run on this isolate. Linux peer
/// credentials are checked before any D-Bus authentication bytes are processed.
class ControlPeerServer {
  ControlPeerServer({
    required this.path,
    required String libraryPath,
    required this.appPid,
    required this.appUid,
    required this.sessionAlive,
    required this.onCall,
    required this.onDisconnect,
  }) : _bus = _BusLibrary(libraryPath);

  final String path;
  final int appPid;
  final int appUid;
  final bool Function() sessionAlive;
  final Future<PeerReply> Function(String method, List<Object> values) onCall;
  final void Function() onDisconnect;
  final _BusLibrary _bus;
  final _socket = _UnixSocketLibrary();
  final _connections = <_PeerConnection>[];
  int _listener = -1;
  Timer? _timer;
  bool _accepted = false;
  bool _closed = false;

  bool get hasPeer => _accepted;

  void start() {
    _listener = _socket.listen(path);
    _timer = Timer.periodic(
      const Duration(milliseconds: 10),
      (_) => _process(),
    );
  }

  void _process() {
    if (_closed) return;
    try {
      if (!sessionAlive()) {
        onDisconnect();
        return;
      }
      if (!_accepted) {
        // Bound each iteration so a rejected peer cannot starve lifetime checks.
        for (var count = 0; count < 8; count++) {
          final descriptor = _socket.accept(_listener);
          if (descriptor < 0) break;
          if (!_socket.matches(descriptor, appPid, appUid) ||
              !sessionAlive() ||
              _connections.length >= 8) {
            _socket.close(descriptor);
            continue;
          }
          _connections.add(_PeerConnection(this, descriptor));
        }
      }
      for (final connection in _connections.toList()) {
        if (!connection.process()) {
          connection.close();
          _connections.remove(connection);
          if (connection.accepted) onDisconnect();
        } else if (connection.ready && !connection.accepted) {
          if (_accepted) {
            connection.close();
            _connections.remove(connection);
          } else {
            connection.accepted = true;
            _accepted = true;
            _socket.close(_listener);
            _listener = -1;
          }
        }
      }
    } catch (_) {
      onDisconnect();
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    if (_listener >= 0) _socket.close(_listener);
    _listener = -1;
    for (final connection in _connections) {
      connection.close();
    }
    _connections.clear();
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      File(path).deleteSync();
    }
  }
}

class _PeerConnection {
  _PeerConnection(this.server, int descriptor) {
    _callback = NativeCallable<_MessageCallback>.isolateLocal(
      _receive,
      exceptionalReturn: -5,
    );
    var ownsDescriptor = false;
    try {
      using((arena) {
        final result = arena<Pointer<Void>>();
        _check(library.newBus(result));
        bus = result.value;
        _check(library.setFd(bus, descriptor, descriptor));
        ownsDescriptor = true;
        final id = arena<_BusId>();
        _check(library.randomId(id));
        _check(library.setServer(bus, 1, id.ref));
        _check(library.setAnonymous(bus, 0));
        _check(library.negotiateFds(bus, 0));
        _check(
          library.addObject(
            bus,
            nullptr,
            controlObjectPath.toNativeUtf8(allocator: arena),
            _callback.nativeFunction,
            nullptr,
          ),
        );
        _check(library.start(bus));
      });
    } catch (_) {
      if (!ownsDescriptor) server._socket.close(descriptor);
      close();
      rethrow;
    }
  }

  final ControlPeerServer server;
  _BusLibrary get library => server._bus;
  Pointer<Void> bus = nullptr;
  late final NativeCallable<_MessageCallback> _callback;
  final _age = Stopwatch()..start();
  bool accepted = false;
  bool _closed = false;

  bool get ready => !_closed && library.isReady(bus) > 0;

  bool process() {
    if (_closed || (!accepted && _age.elapsed > const Duration(seconds: 10))) {
      return false;
    }
    for (var count = 0; count < 32; count++) {
      final result = library.process(bus, nullptr);
      if (result < 0) return false;
      if (result == 0) break;
    }
    return library.isOpen(bus) > 0;
  }

  int _receive(Pointer<Void> message, Pointer<Void> _, Pointer<_BusError> _) {
    if (server._accepted && !accepted) return -13;
    final interface = library.getInterface(message);
    final member = library.getMember(message);
    if (interface == nullptr || member == nullptr) return 0;
    if (interface.toDartString() == 'org.freedesktop.DBus.Introspectable' &&
        member.toDartString() == 'Introspect') {
      if (library.signature(message, 1).toDartString().isNotEmpty) return -22;
      _reply(message, PeerReply([_introspectionXml()]));
      return 1;
    }
    if (interface.toDartString() != controlInterface) return 0;
    final method = member.toDartString();
    library.refMessage(message);
    unawaited(_handle(message, method));
    return 1;
  }

  Future<void> _handle(Pointer<Void> message, String method) async {
    try {
      final PeerReply reply;
      if (!server.sessionAlive()) {
        reply = const PeerReply.error(
          '$controlInterface.Error.Unavailable',
          'the app session has ended',
        );
      } else {
        final arguments = _readArguments(message, method);
        reply = await server.onCall(method, arguments);
      }
      if (!_closed) _reply(message, reply);
    } on FormatException catch (error) {
      if (!_closed) {
        _reply(
          message,
          PeerReply.error(
            'org.freedesktop.DBus.Error.InvalidArgs',
            error.message,
          ),
        );
      }
    } catch (_) {
      if (!_closed) {
        _reply(
          message,
          const PeerReply.error(
            '$controlInterface.Error.Unavailable',
            'control session failed',
          ),
        );
      }
      server.onDisconnect();
    } finally {
      library.unrefMessage(message);
    }
  }

  List<Object> _readArguments(Pointer<Void> message, String method) {
    final signature = _methods[method]?.$1;
    if (signature == null) throw const FormatException('unknown method');
    if (library.signature(message, 1).toDartString() != signature) {
      throw const FormatException('method arguments have the wrong types');
    }
    return using((arena) {
      if (signature == 'ay') {
        final data = arena<Pointer<Uint8>>();
        final size = arena<UintPtr>();
        _check(library.readArray(message, 121, data, size));
        final maximum = method == 'ApplyFanCurve' ? 65536 : 16777216;
        if (size.value == 0 || size.value > maximum) {
          throw FormatException(
            size.value == 0
                ? 'payload must not be empty'
                : 'payload exceeds maximum size',
          );
        }
        return <Object>[Uint8List.fromList(data.value.asTypedList(size.value))];
      }
      final values = <Object>[];
      for (final type in signature.codeUnits) {
        if (type == 115) {
          final text = arena<Pointer<Utf8>>();
          _check(library.readBasic(message, type, text.cast()));
          values.add(text.value.toDartString());
        } else {
          final number = arena<Uint32>();
          _check(library.readBasic(message, type, number.cast()));
          values.add(type == 98 ? number.value != 0 : number.value);
        }
      }
      return values;
    });
  }

  void _reply(Pointer<Void> request, PeerReply reply) {
    using((arena) {
      final response = arena<Pointer<Void>>();
      if (reply.errorName case final name?) {
        final error = arena<_BusError>();
        error.ref
          ..name = name.toNativeUtf8(allocator: arena)
          ..message = (reply.errorMessage ?? '').toNativeUtf8(allocator: arena)
          ..needFree = 0;
        _check(library.newError(request, response, error));
      } else {
        _check(library.newReturn(request, response));
      }
      try {
        for (final value in reply.values) {
          switch (value) {
            case int():
              final number = arena<Uint32>()..value = value;
              _check(library.appendBasic(response.value, 117, number.cast()));
            case String():
              _check(
                library.appendBasic(
                  response.value,
                  115,
                  value.toNativeUtf8(allocator: arena).cast(),
                ),
              );
            case List<String>():
              _check(
                library.openContainer(
                  response.value,
                  97,
                  's'.toNativeUtf8(allocator: arena),
                ),
              );
              for (final text in value) {
                _check(
                  library.appendBasic(
                    response.value,
                    115,
                    text.toNativeUtf8(allocator: arena).cast(),
                  ),
                );
              }
              _check(library.closeContainer(response.value));
            default:
              throw StateError('Unsupported control reply value.');
          }
        }
        _check(library.send(bus, response.value, nullptr));
      } finally {
        library.unrefMessage(response.value);
      }
    });
  }

  void close() {
    if (_closed) return;
    _closed = true;
    if (bus != nullptr) library.closeUnref(bus);
    bus = nullptr;
    _callback.close();
  }
}

void _check(int result) {
  if (result < 0) throw OSError('D-Bus operation failed.', -result);
}

/// Signatures from the public sd-bus API; no private library structures are used.
class _BusLibrary {
  _BusLibrary(String path) : _library = DynamicLibrary.open(path);

  final DynamicLibrary _library;
  late final newBus = _library
      .lookupFunction<
        Int32 Function(Pointer<Pointer<Void>>),
        int Function(Pointer<Pointer<Void>>)
      >('sd_bus_new');
  late final setFd = _library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Int32, Int32),
        int Function(Pointer<Void>, int, int)
      >('sd_bus_set_fd');
  late final randomId = _library
      .lookupFunction<
        Int32 Function(Pointer<_BusId>),
        int Function(Pointer<_BusId>)
      >('sd_id128_randomize');
  late final setServer = _library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Int32, _BusId),
        int Function(Pointer<Void>, int, _BusId)
      >('sd_bus_set_server');
  late final setAnonymous = _library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Int32),
        int Function(Pointer<Void>, int)
      >('sd_bus_set_anonymous');
  late final negotiateFds = _library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Int32),
        int Function(Pointer<Void>, int)
      >('sd_bus_negotiate_fds');
  late final addObject = _library
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Pointer<Pointer<Void>>,
          Pointer<Utf8>,
          Pointer<NativeFunction<_MessageCallback>>,
          Pointer<Void>,
        ),
        int Function(
          Pointer<Void>,
          Pointer<Pointer<Void>>,
          Pointer<Utf8>,
          Pointer<NativeFunction<_MessageCallback>>,
          Pointer<Void>,
        )
      >('sd_bus_add_object');
  late final start = _library
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('sd_bus_start');
  late final process = _library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>),
        int Function(Pointer<Void>, Pointer<Pointer<Void>>)
      >('sd_bus_process');
  late final isReady = _library
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('sd_bus_is_ready');
  late final isOpen = _library
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('sd_bus_is_open');
  late final closeUnref = _library
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('sd_bus_close_unref');
  late final getInterface = _library
      .lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>),
        Pointer<Utf8> Function(Pointer<Void>)
      >('sd_bus_message_get_interface');
  late final getMember = _library
      .lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>),
        Pointer<Utf8> Function(Pointer<Void>)
      >('sd_bus_message_get_member');
  late final signature = _library
      .lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>, Int32),
        Pointer<Utf8> Function(Pointer<Void>, int)
      >('sd_bus_message_get_signature');
  late final refMessage = _library
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('sd_bus_message_ref');
  late final unrefMessage = _library
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('sd_bus_message_unref');
  late final readBasic = _library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Int8, Pointer<Void>),
        int Function(Pointer<Void>, int, Pointer<Void>)
      >('sd_bus_message_read_basic');
  late final readArray = _library
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Int8,
          Pointer<Pointer<Uint8>>,
          Pointer<UintPtr>,
        ),
        int Function(
          Pointer<Void>,
          int,
          Pointer<Pointer<Uint8>>,
          Pointer<UintPtr>,
        )
      >('sd_bus_message_read_array');
  late final newReturn = _library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>),
        int Function(Pointer<Void>, Pointer<Pointer<Void>>)
      >('sd_bus_message_new_method_return');
  late final newError = _library
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Pointer<Pointer<Void>>,
          Pointer<_BusError>,
        ),
        int Function(Pointer<Void>, Pointer<Pointer<Void>>, Pointer<_BusError>)
      >('sd_bus_message_new_method_error');
  late final appendBasic = _library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Int8, Pointer<Void>),
        int Function(Pointer<Void>, int, Pointer<Void>)
      >('sd_bus_message_append_basic');
  late final openContainer = _library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Int8, Pointer<Utf8>),
        int Function(Pointer<Void>, int, Pointer<Utf8>)
      >('sd_bus_message_open_container');
  late final closeContainer = _library
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('sd_bus_message_close_container');
  late final send = _library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Void>, Pointer<Uint64>),
        int Function(Pointer<Void>, Pointer<Void>, Pointer<Uint64>)
      >('sd_bus_send');
}

class _UnixSocketLibrary {
  final _library = DynamicLibrary.process();
  late final _socket = _library
      .lookupFunction<
        Int32 Function(Int32, Int32, Int32),
        int Function(int, int, int)
      >('socket');
  late final _bind = _library
      .lookupFunction<
        Int32 Function(Int32, Pointer<Void>, Uint32),
        int Function(int, Pointer<Void>, int)
      >('bind');
  late final _listen = _library
      .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
        'listen',
      );
  late final _accept = _library
      .lookupFunction<
        Int32 Function(Int32, Pointer<Void>, Pointer<Uint32>, Int32),
        int Function(int, Pointer<Void>, Pointer<Uint32>, int)
      >('accept4');
  late final _peer = _library
      .lookupFunction<
        Int32 Function(Int32, Int32, Int32, Pointer<Void>, Pointer<Uint32>),
        int Function(int, int, int, Pointer<Void>, Pointer<Uint32>)
      >('getsockopt');
  late final _chmod = _library
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Uint32),
        int Function(Pointer<Utf8>, int)
      >('chmod');
  late final close = _library
      .lookupFunction<Int32 Function(Int32), int Function(int)>('close');

  int listen(String path) => using((arena) {
    final bytes = utf8.encode(path);
    if (bytes.length >= 108) {
      throw const FormatException('Socket path is too long.');
    }
    final address = arena<Uint8>(110);
    address.cast<Uint16>().value = 1; // AF_UNIX.
    address.asTypedList(110).setRange(2, 2 + bytes.length, bytes);
    address[2 + bytes.length] = 0;
    final descriptor = _socket(1, 1 | 0x80000 | 0x800, 0);
    if (descriptor < 0) {
      throw const SocketException('Could not open control socket.');
    }
    if (_bind(descriptor, address.cast(), 2 + bytes.length + 1) != 0 ||
        _chmod(path.toNativeUtf8(allocator: arena), 438) != 0 ||
        _listen(descriptor, 8) != 0) {
      close(descriptor);
      throw const SocketException('Could not listen on control socket.');
    }
    return descriptor;
  });

  int accept(int descriptor) =>
      _accept(descriptor, nullptr, nullptr, 0x80000 | 0x800);

  bool matches(int descriptor, int pid, int uid) => using((arena) {
    final credentials = arena<Int32>(3);
    final size = arena<Uint32>()..value = 12;
    return _peer(descriptor, 1, 17, credentials.cast(), size) == 0 &&
        size.value == 12 &&
        credentials[0] == pid &&
        credentials.cast<Uint32>()[1] == uid;
  });
}
