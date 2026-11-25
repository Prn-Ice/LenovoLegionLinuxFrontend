import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _OpenNative = Int32 Function(Pointer<Utf8>, Int32);
typedef _OpenDart = int Function(Pointer<Utf8>, int);
typedef _IoctlNative = Int32 Function(Int32, UnsignedLong, Pointer<Uint8>);
typedef _IoctlDart = int Function(int, int, Pointer<Uint8>);
typedef _CloseNative = Int32 Function(Int32);
typedef _CloseDart = int Function(int);

/// Opens and closes HID devices and exchanges Linux feature reports.
/// Production calls libc; tests record calls without opening a hidraw node.
abstract interface class SpectrumHidIo {
  int open(String path, int flags);

  int ioctl(int fd, int request, Uint8List buffer);

  int close(int fd);
}

final class NativeSpectrumHidIo implements SpectrumHidIo {
  NativeSpectrumHidIo._();

  static final NativeSpectrumHidIo instance = NativeSpectrumHidIo._();
  static final DynamicLibrary _libc = DynamicLibrary.process();
  static final _open = _libc.lookupFunction<_OpenNative, _OpenDart>('open');
  static final _ioctl = _libc.lookupFunction<_IoctlNative, _IoctlDart>('ioctl');
  static final _close = _libc.lookupFunction<_CloseNative, _CloseDart>('close');

  @override
  int open(String path, int flags) {
    final nativePath = path.toNativeUtf8();
    try {
      return _open(nativePath, flags);
    } finally {
      malloc.free(nativePath);
    }
  }

  @override
  int ioctl(int fd, int request, Uint8List buffer) {
    final pointer = malloc<Uint8>(buffer.length);
    try {
      pointer.asTypedList(buffer.length).setAll(0, buffer);
      final result = _ioctl(fd, request, pointer);
      if (result >= 0) {
        buffer.setAll(0, pointer.asTypedList(buffer.length));
      }
      return result;
    } finally {
      malloc.free(pointer);
    }
  }

  @override
  int close(int fd) => _close(fd);
}
