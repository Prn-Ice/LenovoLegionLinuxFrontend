import 'dart:collection';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

final class _PollDescriptor extends Struct {
  @Int32()
  external int descriptor;

  @Int16()
  external int events;

  @Int16()
  external int returnedEvents;
}

/// Linux metadata read through statx, whose layout is independent of libc.
class LinuxFileInfo {
  const LinuxFileInfo(this.uid, this.mode, this.links);

  final int uid;
  final int mode;
  final int links;

  bool get directory => (mode & 0xf000) == 0x4000;
  bool get symbolicLink => (mode & 0xf000) == 0xa000;
  bool get regularFile => (mode & 0xf000) == 0x8000;
}

/// Owns the Linux calls needed to check trusted paths and inherited processes.
class LinuxResources {
  final _symbols = DynamicLibrary.process();

  late final _openAt = _symbols
      .lookupFunction<
        Int32 Function(Int32, Pointer<Utf8>, Int32),
        int Function(int, Pointer<Utf8>, int)
      >('openat');
  late final close = _symbols
      .lookupFunction<Int32 Function(Int32), int Function(int)>('close');
  late final _statx = _symbols
      .lookupFunction<
        Int32 Function(Int32, Pointer<Utf8>, Int32, Uint32, Pointer<Uint8>),
        int Function(int, Pointer<Utf8>, int, int, Pointer<Uint8>)
      >('statx');
  late final _readlinkAt = _symbols
      .lookupFunction<
        IntPtr Function(Int32, Pointer<Utf8>, Pointer<Uint8>, UintPtr),
        int Function(int, Pointer<Utf8>, Pointer<Uint8>, int)
      >('readlinkat');
  late final _poll = _symbols
      .lookupFunction<
        Int32 Function(Pointer<_PollDescriptor>, UintPtr, Int32),
        int Function(Pointer<_PollDescriptor>, int, int)
      >('poll');
  late final _chmod = _symbols
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Uint32),
        int Function(Pointer<Utf8>, int)
      >('chmod');
  late final _uid = _symbols.lookupFunction<Uint32 Function(), int Function()>(
    'getuid',
  );
  late final _effectiveUid = _symbols
      .lookupFunction<Uint32 Function(), int Function()>('geteuid');

  bool get isRoot => _uid() == 0 && _effectiveUid() == 0;

  int openPath(String path, {int directory = -100}) => using(
    (arena) => _openAt(
      directory,
      path.toNativeUtf8(allocator: arena),
      0x200000 | 0x20000 | 0x80000,
    ),
  ); // O_PATH, NOFOLLOW, CLOEXEC.

  LinuxFileInfo inspectDescriptor(int descriptor) => using((arena) {
    final buffer = arena<Uint8>(256);
    if (_statx(
          descriptor,
          ''.toNativeUtf8(allocator: arena),
          0x1100,
          0x7ff,
          buffer,
        ) !=
        0) {
      throw const FileSystemException('Could not inspect the opened path.');
    }
    final fields = ByteData.sublistView(buffer.asTypedList(256));
    return LinuxFileInfo(
      fields.getUint32(20, Endian.host),
      fields.getUint16(28, Endian.host),
      fields.getUint32(16, Endian.host),
    );
  });

  LinuxFileInfo inspectPath(String path) {
    final descriptor = openPath(path);
    if (descriptor < 0) {
      throw FileSystemException('Could not open the path.', path);
    }
    try {
      return inspectDescriptor(descriptor);
    } finally {
      close(descriptor);
    }
  }

  String _readLink(int directory, String path) => using((arena) {
    final buffer = arena<Uint8>(4096);
    final length = _readlinkAt(
      directory,
      path.toNativeUtf8(allocator: arena),
      buffer,
      4096,
    );
    if (length <= 0 || length >= 4096) {
      throw FileSystemException('Could not read the symbolic link.', path);
    }
    return utf8.decode(buffer.asTypedList(length));
  });

  void setMode(String path, int mode) {
    using((arena) {
      if (_chmod(path.toNativeUtf8(allocator: arena), mode) != 0) {
        throw FileSystemException('Could not set file permissions.', path);
      }
    });
  }

  bool processAlive(int descriptor) => using((arena) {
    if (descriptor < 0) return false;
    final state = arena<_PollDescriptor>();
    state.ref
      ..descriptor = descriptor
      ..events = 1
      ..returnedEvents = 0;
    return _poll(state, 1, 0) == 0;
  });

  int pinnedProcess(int descriptor) {
    final fields = File('/proc/self/fdinfo/$descriptor').readAsLinesSync();
    final process = fields.firstWhere((line) => line.startsWith('Pid:'));
    return int.parse(process.substring(4).trim());
  }

  /// Checks every directory and symlink before accepting a root-owned executable.
  String trustedExecutable(String requested) {
    if (!requested.startsWith('/') ||
        requested.contains('\u0000') ||
        utf8.encode(requested).length >= 4096) {
      throw const FileSystemException('Invalid executable path.');
    }
    final parts = ListQueue<String>();
    void prepend(String path) {
      final names = path.split('/').where((p) => p.isNotEmpty && p != '.');
      for (final name in names.toList().reversed) {
        parts.addFirst(name);
      }
    }

    bool safeDirectory(LinuxFileInfo info) =>
        info.uid == 0 &&
        info.directory &&
        (info.mode & 2) == 0 &&
        ((info.mode & 16) == 0 || (info.mode & 512) != 0);

    prepend(requested);
    var directory = openPath('/');
    var links = 0;
    try {
      if (directory < 0 || !safeDirectory(inspectDescriptor(directory))) {
        throw const FileSystemException('The root directory is not trusted.');
      }
      while (parts.isNotEmpty) {
        var next = openPath(parts.removeFirst(), directory: directory);
        try {
          if (next < 0) {
            throw FileSystemException(
              'Could not open the executable.',
              requested,
            );
          }
          final info = inspectDescriptor(next);
          if (info.uid != 0) {
            throw const FileSystemException(
              'The executable path is not root-owned.',
            );
          }
          if (info.symbolicLink) {
            if (++links > 40) {
              throw const FileSystemException('Too many symbolic links.');
            }
            final target = _readLink(next, '');
            if (target.startsWith('/')) {
              close(directory);
              directory = openPath('/');
            }
            prepend(target);
          } else if (info.directory) {
            if (!safeDirectory(info)) {
              throw const FileSystemException(
                'The executable directory is writable by other users.',
              );
            }
            close(directory);
            directory = next;
            next = -1;
          } else {
            if (parts.isNotEmpty ||
                !info.regularFile ||
                info.links == 0 ||
                (info.mode & 18) != 0 ||
                (info.mode & 73) == 0) {
              throw const FileSystemException(
                'The executable has unsafe permissions.',
              );
            }
            return _readLink(-100, '/proc/self/fd/$next');
          }
        } finally {
          if (next >= 0) close(next);
        }
      }
      throw const FileSystemException('The executable path names a directory.');
    } finally {
      if (directory >= 0) close(directory);
    }
  }

  String findHostCli() {
    for (final candidate in [
      '/run/current-system/sw/bin/legion_cli',
      '/nix/var/nix/profiles/default/bin/legion_cli',
      '/usr/bin/legion_cli',
      '/usr/local/bin/legion_cli',
    ]) {
      if (FileSystemEntity.typeSync(candidate, followLinks: false) ==
          FileSystemEntityType.notFound) {
        continue;
      }
      return trustedExecutable(candidate);
    }
    throw const FileSystemException(
      'Install legion_cli in an administrator-controlled host location.',
    );
  }
}
