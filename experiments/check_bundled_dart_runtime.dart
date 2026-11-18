import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

/// Checks a compiled runtime with local files and sockets, without hardware.
Future<void> main() async {
  final symbols = DynamicLibrary.process();
  final availableSymbols = {
    for (final name in [
      'getuid',
      'memfd_create',
      'pidfd_open',
      'fcntl',
      'sendmsg',
      'recvmsg',
      'getsockopt',
      'syscall',
    ])
      name: symbols.providesSymbol(name),
  };
  final getUserId = symbols.lookupFunction<Uint32 Function(), int Function()>(
    'getuid',
  );
  final directory = Directory.systemTemp.createTempSync('dart-runtime-check-');
  RawServerSocket? listener;
  RawSocket? client;
  RawSocket? peer;
  try {
    final file = File('${directory.path}/message');
    file.writeAsStringSync('Dart runtime file check');
    final filePassed = file.readAsStringSync() == 'Dart runtime file check';
    final address = InternetAddress(
      '${directory.path}/socket',
      type: InternetAddressType.unix,
    );
    listener = await RawServerSocket.bind(address, 0);
    final accepted = listener.first;
    client = await RawSocket.connect(address, 0);
    peer = await accepted.timeout(const Duration(seconds: 5));

    // Linux x86-64 uses three 32-bit fields for SO_PEERCRED (PID, UID, GID).
    const socketLevel = 1;
    const peerCredentialsOption = 17;
    final bytes = peer.getRawOption(
      RawSocketOption(socketLevel, peerCredentialsOption, Uint8List(12)),
    );
    final credentials = ByteData.sublistView(bytes);
    final peerPassed =
        credentials.getInt32(0, Endian.host) == pid &&
        credentials.getUint32(4, Endian.host) == getUserId();
    final mappedFiles =
        File('/proc/self/maps')
            .readAsLinesSync()
            .where((line) => line.contains('/'))
            .map((line) => line.substring(line.indexOf('/')))
            .toSet()
            .toList()
          ..sort();
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'dartVersion': Platform.version,
        'resolvedExecutable': Platform.resolvedExecutable,
        'kernelExecutable': Link('/proc/self/exe').targetSync(),
        'filePassed': filePassed,
        'peerPassed': peerPassed,
        'availableSymbols': availableSymbols,
        'mappedFiles': mappedFiles,
      }),
    );
    if (!filePassed || !peerPassed) {
      exitCode = 1;
    }
  } finally {
    client?.close();
    peer?.close();
    await listener?.close();
    directory.deleteSync(recursive: true);
  }
}
