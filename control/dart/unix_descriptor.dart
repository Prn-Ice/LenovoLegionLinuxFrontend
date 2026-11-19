import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

final class _IoVector extends Struct {
  external Pointer<Uint8> data;
  @UintPtr()
  external int length;
}

final class _MessageHeader extends Struct {
  external Pointer<Void> name;
  @Uint32()
  external int nameLength;
  external Pointer<_IoVector> vectors;
  @UintPtr()
  external int vectorCount;
  external Pointer<Uint8> control;
  @UintPtr()
  external int controlLength;
  @Int32()
  external int flags;
}

final _libc = DynamicLibrary.process();
final _socket = _libc
    .lookupFunction<
      Int32 Function(Int32, Int32, Int32),
      int Function(int, int, int)
    >('socket');
final _connect = _libc
    .lookupFunction<
      Int32 Function(Int32, Pointer<Uint8>, Uint32),
      int Function(int, Pointer<Uint8>, int)
    >('connect');
final _send = _libc
    .lookupFunction<
      IntPtr Function(Int32, Pointer<_MessageHeader>, Int32),
      int Function(int, Pointer<_MessageHeader>, int)
    >('sendmsg');
final _close = _libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
  'close',
);

/// Transfers a duplicate of an existing descriptor into Dart's public API.
///
/// SCM_RIGHTS preserves the open file description, including its flock lock.
/// Reopening /proc/self/fd would lose that ownership. The caller retains its
/// descriptor; the returned handle owns the received duplicate.
Future<ResourceHandle> resourceHandleForDescriptor(int descriptor) async {
  final directory = await Directory.systemTemp.createTemp('legion-fd-');
  final path = '${directory.path}/fd';
  RawServerSocket? listener;
  RawSocket? receiver;
  StreamSubscription<RawSocketEvent>? subscription;
  var sender = -1;
  try {
    listener = await RawServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    final accepted = listener.first;
    sender = _connectSender(path);
    receiver = await accepted.timeout(const Duration(seconds: 3));
    final received = Completer<ResourceHandle>();
    subscription = receiver.listen(
      (event) {
        if (event != RawSocketEvent.read || received.isCompleted) return;
        final message = receiver!.readMessage();
        if (message == null) return;
        final handles = [
          for (final control in message.controlMessages)
            ...control.extractHandles(),
        ];
        if (handles.length != 1) {
          for (final handle in handles) {
            unawaited(handle.toFile().close());
          }
          received.completeError(
            const FileSystemException(
              'Descriptor transfer returned the wrong handle count.',
            ),
          );
          return;
        }
        received.complete(handles.single);
      },
      onError: (Object error, StackTrace stack) {
        if (!received.isCompleted) received.completeError(error, stack);
      },
    );
    _sendDescriptor(sender, descriptor);
    return await received.future.timeout(const Duration(seconds: 3));
  } finally {
    await subscription?.cancel();
    await receiver?.close();
    if (sender >= 0) _close(sender);
    await listener?.close();
    await directory.delete(recursive: true);
  }
}

int _connectSender(String path) => using((arena) {
  final encoded = path.toNativeUtf8(allocator: arena);
  final length = encoded.length;
  if (length >= 108) {
    throw const FileSystemException('Descriptor socket path is too long.');
  }
  final address = arena<Uint8>(110);
  address.cast<Uint16>().value = 1;
  address
      .asTypedList(110)
      .setRange(2, 2 + length, encoded.cast<Uint8>().asTypedList(length));
  address[2 + length] = 0;
  final socket = _socket(1, 1 | 0x80000, 0);
  if (socket < 0) {
    throw const SocketException('Could not create descriptor socket.');
  }
  if (_connect(socket, address, 2 + length + 1) != 0) {
    _close(socket);
    throw const SocketException('Could not connect descriptor socket.');
  }
  return socket;
});

void _sendDescriptor(int socket, int descriptor) {
  using((arena) {
    final vector = arena<_IoVector>();
    vector.ref
      ..data = arena<Uint8>()
      ..length = 1;
    final control = arena<Uint8>(24);
    control.cast<UintPtr>().value = 20;
    (control + 8).cast<Int32>().value = 1; // SOL_SOCKET.
    (control + 12).cast<Int32>().value = 1; // SCM_RIGHTS.
    (control + 16).cast<Int32>().value = descriptor;
    final message = arena<_MessageHeader>();
    message.ref
      ..name = nullptr
      ..nameLength = 0
      ..vectors = vector
      ..vectorCount = 1
      ..control = control
      ..controlLength = 24
      ..flags = 0;
    if (_send(socket, message, 0x4000) != 1) {
      // MSG_NOSIGNAL.
      throw const FileSystemException('Could not transfer the descriptor.');
    }
  });
}
