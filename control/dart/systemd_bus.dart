import 'dart:async';
import 'dart:ffi';

import 'package:dbus/dbus.dart';
import 'package:ffi/ffi.dart';

/// A borrowed Linux descriptor. sd-bus duplicates it while appending the value.
class LinuxDescriptorValue extends DBusValue {
  LinuxDescriptorValue(this.descriptor);
  final int descriptor;
  @override
  DBusSignature get signature => DBusSignature('h');
  @override
  int toNative() => descriptor;
}

final class _Error extends Struct {
  external Pointer<Utf8> name;
  external Pointer<Utf8> message;
  @Int32()
  external int allocated;
}

typedef _Callback = Int32 Function(
  Pointer<Void>,
  Pointer<Void>,
  Pointer<_Error>,
);

/// Uses systemd's public asynchronous bus API for descriptor-bearing requests.
///
/// DBusValue supplies typed values only. libsystemd handles authentication,
/// message framing, descriptor ownership, and call deadlines.
class SystemdBusClient extends DBusClient {
  SystemdBusClient({required String libraryPath, required String address})
    : _api = _Api(libraryPath),
      super(DBusAddress(address)) {
    using((arena) {
      final result = arena<Pointer<Void>>();
      _check(_api.create(result));
      _bus = result.value;
      try {
        _check(_api.address(_bus, address.toNativeUtf8(allocator: arena)));
        _check(_api.client(_bus, 1));
        _check(_api.timeout(_bus, 3000000));
        _check(_api.start(_bus));
      } catch (_) {
        _api.close(_bus);
        _bus = nullptr;
        rethrow;
      }
    });
    _timer = Timer.periodic(
      const Duration(milliseconds: 10),
      (_) => _process(),
    );
    _owners.onListen = _watchOwners;
  }

  final _Api _api;
  Pointer<Void> _bus = nullptr;
  Timer? _timer;
  bool _closed = false;
  final _pending = <_PendingCall>{};
  final _owners = StreamController<DBusNameOwnerChangedEvent>.broadcast();
  NativeCallable<_Callback>? _ownerCallback;
  Pointer<Void> _ownerSlot = nullptr;

  @override
  Stream<DBusNameOwnerChangedEvent> get nameOwnerChanged => _owners.stream;

  void _watchOwners() {
    if (_closed || _ownerCallback != null) return;
    _ownerCallback = NativeCallable<_Callback>.isolateLocal((
      Pointer<Void> message,
      Pointer<Void> _,
      Pointer<_Error> _,
    ) {
      try {
        final values = _readValues(message);
        final previous = values[1].asString();
        final next = values[2].asString();
        _owners.add(
          DBusNameOwnerChangedEvent(
            values[0].asString(),
            oldOwner: previous.isEmpty ? null : previous,
            newOwner: next.isEmpty ? null : next,
          ),
        );
      } catch (error, stack) {
        _owners.addError(error, stack);
      }
      return 0;
    }, exceptionalReturn: -5);
    try {
      using((arena) {
        final slot = arena<Pointer<Void>>();
        _check(
          _api.match(
            _bus,
            slot,
            "type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0='org.freedesktop.systemd1'"
                .toNativeUtf8(allocator: arena),
            _ownerCallback!.nativeFunction,
            nullptr,
          ),
        );
        _ownerSlot = slot.value;
      });
    } catch (error, stack) {
      _owners.addError(error, stack);
    }
  }

  void _process() {
    if (_closed) return;
    for (var count = 0; count < 32; count++) {
      final result = _api.process(_bus, nullptr);
      if (result < 0) {
        unawaited(close());
        return;
      }
      if (result == 0) break;
    }
  }

  @override
  Future<DBusMethodSuccessResponse> callMethod({
    String? destination,
    required DBusObjectPath path,
    String? interface,
    required String name,
    Iterable<DBusValue> values = const [],
    DBusSignature? replySignature,
    bool noReplyExpected = false,
    bool noAutoStart = false,
    bool allowInteractiveAuthorization = false,
  }) async {
    if (_closed) throw StateError('The systemd connection is closed.');
    if (noReplyExpected || allowInteractiveAuthorization) {
      throw ArgumentError(
        'The managed runner requires noninteractive replies.',
      );
    }
    final call = _PendingCall();
    call.callback = NativeCallable<_Callback>.isolateLocal((
      Pointer<Void> message,
      Pointer<Void> _,
      Pointer<_Error> _,
    ) {
      try {
        final error = _api.error(message);
        if (error != nullptr && error.ref.name != nullptr) {
          throw DBusMethodResponseException(
            DBusMethodErrorResponse(error.ref.name.toDartString(), [
              DBusString(
                error.ref.message == nullptr
                    ? ''
                    : error.ref.message.toDartString(),
              ),
            ]),
          );
        }
        final actual = _api.signature(message, 1).toDartString();
        if (replySignature != null && actual != replySignature.value) {
          throw FormatException('Unexpected $name reply signature: $actual');
        }
        call.result.complete(DBusMethodSuccessResponse(_readValues(message)));
      } catch (error, stack) {
        call.result.completeError(error, stack);
      }
      return 1;
    }, exceptionalReturn: -5);
    _pending.add(call);
    try {
      using((arena) {
        final message = arena<Pointer<Void>>();
        _check(
          _api.newCall(
            _bus,
            message,
            destination?.toNativeUtf8(allocator: arena) ?? nullptr,
            path.value.toNativeUtf8(allocator: arena),
            interface?.toNativeUtf8(allocator: arena) ?? nullptr,
            name.toNativeUtf8(allocator: arena),
          ),
        );
        try {
          if (noAutoStart) _check(_api.autoStart(message.value, 0));
          for (final value in values) {
            _append(message.value, value, arena);
          }
          final slot = arena<Pointer<Void>>();
          _check(
            _api.call(
              _bus,
              slot,
              message.value,
              call.callback.nativeFunction,
              nullptr,
              3000000,
            ),
          );
          call.slot = slot.value;
        } finally {
          _api.unrefMessage(message.value);
        }
      });
      return await call.result.future;
    } finally {
      _pending.remove(call);
      call.close(_api);
    }
  }

  void _append(Pointer<Void> message, DBusValue value, Arena arena) {
    void container(int type, String contents, Iterable<DBusValue> children) {
      _check(_api.open(message, type, contents.toNativeUtf8(allocator: arena)));
      for (final child in children) {
        _append(message, child, arena);
      }
      _check(_api.finish(message));
    }

    switch (value) {
      case DBusArray():
        container(97, value.childSignature.value, value.children);
      case DBusStruct():
        final signature = value.signature.value;
        container(
          114,
          signature.substring(1, signature.length - 1),
          value.children,
        );
      case DBusVariant():
        container(118, value.value.signature.value, [value.value]);
      case DBusString():
        _check(
          _api.append(
            message,
            115,
            value.value.toNativeUtf8(allocator: arena).cast(),
          ),
        );
      case DBusBoolean():
        final data = arena<Int32>()..value = value.value ? 1 : 0;
        _check(_api.append(message, 98, data.cast()));
      case DBusUint64():
        final data = arena<Uint64>()..value = value.value;
        _check(_api.append(message, 116, data.cast()));
      case DBusUint32():
        final data = arena<Uint32>()..value = value.value;
        _check(_api.append(message, 117, data.cast()));
      case DBusInt32():
        final data = arena<Int32>()..value = value.value;
        _check(_api.append(message, 105, data.cast()));
      case LinuxDescriptorValue():
        final data = arena<Int32>()..value = value.descriptor;
        _check(_api.append(message, 104, data.cast()));
      default:
        throw ArgumentError('Unsupported systemd argument: ${value.signature}');
    }
  }

  List<DBusValue> _readValues(Pointer<Void> message) {
    final signature = DBusSignature(_api.signature(message, 1).toDartString());
    return using(
      (arena) => [
        for (final type in signature.split()) _read(message, type.value, arena),
      ],
    );
  }

  DBusValue _read(Pointer<Void> message, String type, Arena arena) {
    List<DBusValue> container(int code, String contents) {
      _check(
        _api.enter(message, code, contents.toNativeUtf8(allocator: arena)),
      );
      final values = <DBusValue>[];
      while (_api.atEnd(message, 0) == 0) {
        for (final child in DBusSignature(contents).split()) {
          values.add(_read(message, child.value, arena));
        }
      }
      _check(_api.exit(message));
      return values;
    }

    switch (type) {
      case 's' || 'o' || 'g':
        final data = arena<Pointer<Utf8>>();
        _check(_api.read(message, type.codeUnitAt(0), data.cast()));
        final value = data.value.toDartString();
        return switch (type) {
          'o' => DBusObjectPath(value),
          'g' => DBusSignature(value),
          _ => DBusString(value),
        };
      case 'y' || 'n' || 'q':
        final data = arena<Uint32>();
        _check(_api.read(message, type.codeUnitAt(0), data.cast()));
        return switch (type) {
          'y' => DBusByte(data.cast<Uint8>().value),
          'n' => DBusInt16(data.cast<Int16>().value),
          _ => DBusUint16(data.cast<Uint16>().value),
        };
      case 'u' || 'i' || 'b':
        final data = arena<Uint32>();
        _check(_api.read(message, type.codeUnitAt(0), data.cast()));
        return switch (type) {
          'u' => DBusUint32(data.value),
          'i' => DBusInt32(data.cast<Int32>().value),
          _ => DBusBoolean(data.value != 0),
        };
      case 't' || 'x' || 'd':
        final data = arena<Uint64>();
        _check(_api.read(message, type.codeUnitAt(0), data.cast()));
        return switch (type) {
          't' => DBusUint64(data.value),
          'x' => DBusInt64(data.cast<Int64>().value),
          _ => DBusDouble(data.cast<Double>().value),
        };
      case 'v':
        final code = arena<Int8>();
        final contents = arena<Pointer<Utf8>>();
        _check(_api.peek(message, code, contents));
        return DBusVariant(
          container(118, contents.value.toDartString()).single,
        );
      case 'a{sv}':
        _check(_api.enter(message, 97, '{sv}'.toNativeUtf8(allocator: arena)));
        final values = <String, DBusValue>{};
        while (_api.atEnd(message, 0) == 0) {
          final entry = container(101, 'sv');
          values[entry[0].asString()] = entry[1].asVariant();
        }
        _check(_api.exit(message));
        return DBusDict.stringVariant(values);
      default:
        if (type.startsWith('(')) {
          return DBusStruct(container(114, type.substring(1, type.length - 1)));
        }
        if (type.startsWith('a')) {
          return DBusArray(
            DBusSignature(type.substring(1)),
            container(97, type.substring(1)),
          );
        }
        throw FormatException('Unsupported systemd reply type: $type');
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    if (_ownerSlot != nullptr) _api.unrefSlot(_ownerSlot);
    _ownerCallback?.close();
    for (final call in _pending.toList()) {
      call.close(_api);
      if (!call.result.isCompleted) {
        call.result.completeError(StateError('The systemd connection closed.'));
      }
    }
    _api.close(_bus);
    _bus = nullptr;
    unawaited(_owners.close());
  }
}

class _PendingCall {
  final result = Completer<DBusMethodSuccessResponse>();
  late final NativeCallable<_Callback> callback;
  Pointer<Void> slot = nullptr;
  bool _closed = false;
  void close(_Api api) {
    if (_closed) return;
    _closed = true;
    if (slot != nullptr) api.unrefSlot(slot);
    callback.close();
  }
}

void _check(int result) {
  if (result < 0) {
    throw StateError('Systemd bus call failed: errno ${-result}.');
  }
}

class _Api {
  _Api(String path) : library = DynamicLibrary.open(path);
  final DynamicLibrary library;
  late final timeout = library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Uint64),
        int Function(Pointer<Void>, int)
      >('sd_bus_set_method_call_timeout');
  late final create = library
      .lookupFunction<
        Int32 Function(Pointer<Pointer<Void>>),
        int Function(Pointer<Pointer<Void>>)
      >('sd_bus_new');
  late final address = library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Utf8>),
        int Function(Pointer<Void>, Pointer<Utf8>)
      >('sd_bus_set_address');
  late final client = library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Int32),
        int Function(Pointer<Void>, int)
      >('sd_bus_set_bus_client');
  late final start = library
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('sd_bus_start');
  late final process = library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>),
        int Function(Pointer<Void>, Pointer<Pointer<Void>>)
      >('sd_bus_process');
  late final close = library
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('sd_bus_close_unref');
  late final unrefSlot = library
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('sd_bus_slot_unref');
  late final unrefMessage = library
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('sd_bus_message_unref');
  late final newCall = library
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Pointer<Pointer<Void>>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Utf8>,
        ),
        int Function(
          Pointer<Void>,
          Pointer<Pointer<Void>>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Utf8>,
        )
      >('sd_bus_message_new_method_call');
  late final call = library
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Pointer<Pointer<Void>>,
          Pointer<Void>,
          Pointer<NativeFunction<_Callback>>,
          Pointer<Void>,
          Uint64,
        ),
        int Function(
          Pointer<Void>,
          Pointer<Pointer<Void>>,
          Pointer<Void>,
          Pointer<NativeFunction<_Callback>>,
          Pointer<Void>,
          int,
        )
      >('sd_bus_call_async');
  late final match = library
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Pointer<Pointer<Void>>,
          Pointer<Utf8>,
          Pointer<NativeFunction<_Callback>>,
          Pointer<Void>,
        ),
        int Function(
          Pointer<Void>,
          Pointer<Pointer<Void>>,
          Pointer<Utf8>,
          Pointer<NativeFunction<_Callback>>,
          Pointer<Void>,
        )
      >('sd_bus_add_match');
  late final error = library
      .lookupFunction<
        Pointer<_Error> Function(Pointer<Void>),
        Pointer<_Error> Function(Pointer<Void>)
      >('sd_bus_message_get_error');
  late final signature = library
      .lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>, Int32),
        Pointer<Utf8> Function(Pointer<Void>, int)
      >('sd_bus_message_get_signature');
  late final append = library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Int8, Pointer<Void>),
        int Function(Pointer<Void>, int, Pointer<Void>)
      >('sd_bus_message_append_basic');
  late final open = library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Int8, Pointer<Utf8>),
        int Function(Pointer<Void>, int, Pointer<Utf8>)
      >('sd_bus_message_open_container');
  late final finish = library
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('sd_bus_message_close_container');
  late final enter = library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Int8, Pointer<Utf8>),
        int Function(Pointer<Void>, int, Pointer<Utf8>)
      >('sd_bus_message_enter_container');
  late final exit = library
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('sd_bus_message_exit_container');
  late final atEnd = library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Int32),
        int Function(Pointer<Void>, int)
      >('sd_bus_message_at_end');
  late final read = library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Int8, Pointer<Void>),
        int Function(Pointer<Void>, int, Pointer<Void>)
      >('sd_bus_message_read_basic');
  late final peek = library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Int8>, Pointer<Pointer<Utf8>>),
        int Function(Pointer<Void>, Pointer<Int8>, Pointer<Pointer<Utf8>>)
      >('sd_bus_message_peek_type');
  late final autoStart = library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Int32),
        int Function(Pointer<Void>, int)
      >('sd_bus_message_set_auto_start');
}
