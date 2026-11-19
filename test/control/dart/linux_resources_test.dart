import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../control/dart/linux_resources.dart';

void main() {
  final linux = LinuxResources();

  test('rejects directory and relative executable names', () {
    expect(
      () => linux.trustedExecutable('/'),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      () => linux.trustedExecutable('relative/path'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test(
    'reads the kernel owner and mode without following symbolic links',
    () async {
      final result = await Process.run('stat', ['-c', '%u', '/']);
      expect(result.exitCode, 0);
      final root = linux.inspectPath('/');
      expect(root.uid, int.parse((result.stdout as String).trim()));
      expect(root.directory, isTrue);
    },
  );

  test('rejects an executable alias crossing a user-controlled directory', () {
    final directory = Directory.systemTemp.createTempSync('trusted-path-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final link = Link('${directory.path}/trusted');
    link.createSync(
      File(Platform.resolvedExecutable).resolveSymbolicLinksSync(),
    );
    expect(linux.inspectPath(link.path).symbolicLink, isTrue);
    expect(
      () => linux.trustedExecutable(link.path),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('observes the pinned child process before and after exit', () async {
    final child = await Process.start('sleep', ['30']);
    addTearDown(() async {
      child.kill(ProcessSignal.sigkill);
      await child.exitCode;
    });
    final syscall = DynamicLibrary.process()
        .lookupFunction<
          IntPtr Function(IntPtr, VarArgs<(Int32, Uint32)>),
          int Function(int, int, int)
        >('syscall');
    final descriptor = syscall(434, child.pid, 0); // Linux x86-64 pidfd_open.
    expect(descriptor, greaterThanOrEqualTo(0));
    addTearDown(() => linux.close(descriptor));
    expect(linux.pinnedProcess(descriptor), child.pid);
    expect(linux.processAlive(descriptor), isTrue);
    child.kill(ProcessSignal.sigkill);
    await child.exitCode;
    expect(linux.processAlive(descriptor), isFalse);
  });
}
