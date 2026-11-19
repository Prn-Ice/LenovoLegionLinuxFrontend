import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../control/dart/unix_descriptor.dart';

final _libc = DynamicLibrary.process();
final _open = _libc
    .lookupFunction<
      Int32 Function(Pointer<Utf8>, Int32, Int32),
      int Function(Pointer<Utf8>, int, int)
    >('open');
final _close = _libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
  'close',
);
final _flock = _libc
    .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
      'flock',
    );

void main() {
  test(
    'SCM_RIGHTS transfer retains the flock until the received handle closes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'legion-lock-test-',
      );
      final path = '${directory.path}/operation.lock';
      var original = using(
        (arena) => _open(path.toNativeUtf8(allocator: arena), 0x42, 0x180),
      );
      addTearDown(() async {
        if (original >= 0) _close(original);
        await directory.delete(recursive: true);
      });
      expect(original, greaterThanOrEqualTo(0));
      expect(_flock(original, 2 | 4), 0);

      final received = await resourceHandleForDescriptor(original);
      _close(original);
      original = -1;

      final competing = using(
        (arena) => _open(path.toNativeUtf8(allocator: arena), 2, 0),
      );
      expect(competing, greaterThanOrEqualTo(0));
      expect(_flock(competing, 2 | 4), isNot(0));

      final receivedFile = received.toFile();
      await receivedFile.close();
      expect(_flock(competing, 2 | 4), 0);
      _close(competing);
    },
    skip: !Platform.isLinux,
  );
}
