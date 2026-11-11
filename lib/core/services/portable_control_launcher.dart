import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/portable_control_endpoint.dart';
import 'legion_control_client.dart';

typedef PortableProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      required Map<String, String> environment,
      required String workingDirectory,
      required bool includeParentEnvironment,
    });

/// Owns the ordinary-user launcher and its bounded readiness exchange.
/// The native launcher obtains host approval and supervises the root helper.
class PortableControlLauncher {
  PortableControlLauncher({
    required this.executable,
    PortableProcessStarter? startProcess,
    Map<String, String>? environment,
    this.startupTimeout = const Duration(seconds: 70),
    this.stopTimeout = const Duration(seconds: 3),
    this.killTimeout = const Duration(seconds: 2),
  }) : _startProcess = startProcess ?? Process.start,
       _environment = _hostEnvironment(environment ?? Platform.environment);

  final String executable;
  final Duration startupTimeout;
  final Duration stopTimeout;
  final Duration killTimeout;
  final PortableProcessStarter _startProcess;
  final Map<String, String> _environment;
  final _ready = Completer<PortableControlEndpoint>();
  final _ended = Completer<LegionControlException>();
  final _stderrDone = Completer<void>();
  final _line = <int>[];
  final _stderr = <int>[];
  StreamSubscription<List<int>>? _stdoutSubscription;
  StreamSubscription<List<int>>? _stderrSubscription;
  Future<PortableControlEndpoint>? _starting;
  Future<void>? _stopping;
  Process? _process;
  PortableControlEndpoint? _endpoint;
  String? _unit;
  int? _exitCode;
  int _stdoutBytes = 0;
  bool _acknowledged = false;
  bool _closed = false;

  /// Completes with the reason the session ended, including explicit close.
  Future<LegionControlException> get ended => _ended.future;

  static Map<String, String> _hostEnvironment(Map<String, String> source) {
    return Map.unmodifiable({
      for (final entry in source.entries)
        if (!entry.key.startsWith('LD_') &&
            !entry.key.startsWith('GIO_') &&
            !const {
              'GCONV_PATH',
              'GI_TYPELIB_PATH',
              'PYTHONPATH',
              'PYTHONHOME',
              'DBUS_SYSTEM_BUS_ADDRESS',
              'APPDIR',
              'APPIMAGE',
              'ARGV0',
              'GTK_PATH',
              'GTK_EXE_PREFIX',
              'GTK_DATA_PREFIX',
              'PATH',
            }.contains(entry.key))
          entry.key: entry.value,
      'PATH': '/run/current-system/sw/bin:/usr/sbin:/usr/bin:/sbin:/bin',
    });
  }

  LegionControlUnavailableException
  _closedError() => const LegionControlUnavailableException(
    'Portable control startup was closed. Start a new app session to retry.',
  );

  Future<PortableControlEndpoint> start() {
    if (_closed) return Future.error(_closedError());
    return _starting ??= _start();
  }

  Future<PortableControlEndpoint> _start() async {
    try {
      return await Future.any([
        _spawnAndRead(),
        _ended.future.then<PortableControlEndpoint>((error) => throw error),
      ]).timeout(startupTimeout);
    } on TimeoutException {
      await close();
      throw const LegionControlTimeoutException(
        'Portable control startup timed out. Check the authentication prompt and start a new app session to retry.',
      );
    } catch (_) {
      await close();
      rethrow;
    }
  }

  Future<PortableControlEndpoint> _spawnAndRead() async {
    if (!executable.startsWith('/')) {
      throw const LegionControlSetupException(
        'The portable helper must have an absolute path inside the app bundle.',
      );
    }
    Process process;
    try {
      process = await _startProcess(
        executable,
        const ['--control'],
        environment: _environment,
        workingDirectory: '/',
        includeParentEnvironment: false,
      );
    } on ProcessException catch (error) {
      throw LegionControlSetupException(
        'Could not start the portable helper. Verify the app files and host libraries. $error',
      );
    }
    _process = process;
    _stdoutSubscription = process.stdout.listen(
      _consumeStdout,
      onError: (Object error) => _fail(
        LegionControlSetupException(
          'Could not read portable helper readiness: $error',
        ),
      ),
      onDone: () {
        if (!_closed && _line.isNotEmpty) {
          _fail(
            const LegionControlSetupException(
              'The portable helper ended with an incomplete readiness message.',
            ),
          );
        }
      },
    );
    _stderrSubscription = process.stderr.listen(
      (bytes) {
        if (_closed) return;
        if (_stderr.length + bytes.length > 8192) {
          _fail(
            const LegionControlSetupException(
              'Portable helper diagnostics exceeded 8 KiB.',
            ),
          );
        } else {
          _stderr.addAll(bytes);
        }
      },
      onError: (Object error) {
        _fail(
          LegionControlSetupException(
            'Could not read portable helper diagnostics: $error',
          ),
        );
      },
      onDone: () => _stderrDone.complete(),
    );
    unawaited(_watchExit(process));
    if (_closed) {
      await close();
      throw _closedError();
    }
    final endpoint = await _ready.future;
    if (_closed || _exitCode != null) throw _closedError();
    return endpoint;
  }

  static final _unitPattern =
      r'legion-bootstrap-probe-[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\.service';
  static final _snapshot = RegExp(
    '^SNAPSHOT_READY launcher=([1-9][0-9]*) unit=($_unitPattern)\$',
  );
  static final _control = RegExp(
    '^CONTROL_READY helper=([1-9][0-9]*) unit=($_unitPattern) address=(\\S+)\$',
  );

  void _consumeStdout(List<int> bytes) {
    if (_closed) return;
    _stdoutBytes += bytes.length;
    if (_stdoutBytes > 64 * 1024) {
      _fail(
        const LegionControlSetupException(
          'Portable helper readiness exceeded 64 KiB.',
        ),
      );
      return;
    }
    for (final byte in bytes) {
      if (_closed) return;
      if (byte == 10) {
        try {
          final line = utf8.decode(_line);
          _line.clear();
          _readLine(line);
        } on FormatException {
          _fail(
            const LegionControlSetupException(
              'The portable helper returned invalid readiness text.',
            ),
          );
        }
      } else if (_line.length >= 4096) {
        _fail(
          const LegionControlSetupException(
            'A portable helper readiness line exceeded 4 KiB.',
          ),
        );
        return;
      } else {
        _line.add(byte);
      }
    }
  }

  void _readLine(String line) {
    final snapshot = _snapshot.firstMatch(line);
    final control = _control.firstMatch(line);
    if (snapshot != null &&
        _unit == null &&
        int.tryParse(snapshot[1]!) == _process!.pid) {
      _unit = snapshot[2];
    } else if (line == 'START_ACKNOWLEDGED' &&
        _unit != null &&
        !_acknowledged) {
      _acknowledged = true;
    } else if (control != null && _endpoint == null && control[2] == _unit) {
      final pid = int.tryParse(control[1]!);
      final directory =
          '/run/${_unit!.substring(0, _unit!.length - 8)}/control.sock';
      final address = RegExp(
        '^unix:path=${RegExp.escape(directory)}(,guid=[0-9a-fA-F]{32})?\$',
      );
      if (pid == null ||
          pid <= 1 ||
          pid > 0x7fffffff ||
          !address.hasMatch(control[3]!)) {
        _fail(
          const LegionControlSetupException(
            'Portable helper identity does not match its launch.',
          ),
        );
        return;
      }
      _endpoint = PortableControlEndpoint(
        address: control[3]!,
        unit: control[2]!,
        helperPid: pid,
      );
    } else {
      _fail(
        const LegionControlSetupException(
          'Unexpected portable helper readiness message.',
        ),
      );
      return;
    }
    if (_endpoint != null &&
        _acknowledged &&
        !_ready.isCompleted &&
        _exitCode == null) {
      _ready.complete(_endpoint);
    }
  }

  Future<void> _watchExit(Process process) async {
    _exitCode = await process.exitCode;
    if (_closed) return;
    if (!_ready.isCompleted) {
      try {
        await _stderrDone.future.timeout(const Duration(seconds: 1));
      } on TimeoutException {
        /* Report exit with diagnostics received so far. */
      }
    }
    if (_closed) return;
    final details = utf8.decode(_stderr, allowMalformed: true).trim();
    final message = 'Portable helper exited with status $_exitCode. $details'
        .trim();
    _fail(
      details.contains('org.freedesktop.DBus.Error.AccessDenied')
          ? LegionControlPermissionDeniedException(message)
          : LegionControlUnavailableException(message),
    );
  }

  void _fail(LegionControlException error) {
    if (_closed) return;
    if (!_ready.isCompleted) _ready.completeError(error);
    if (!_ended.isCompleted) _ended.complete(error);
    unawaited(
      close().catchError((Object _) {
        // Explicit close still returns the cached cleanup error to the owner.
      }),
    );
  }

  Future<void> close() {
    if (!_closed) {
      _closed = true;
      if (!_ended.isCompleted) _ended.complete(_closedError());
    }
    final process = _process;
    // Process.start cannot be cancelled. A late child is stopped in _spawnAndRead.
    return process == null ? Future.value() : (_stopping ??= _stop(process));
  }

  Future<void> _stop(Process process) async {
    try {
      if (_exitCode == null) process.kill(ProcessSignal.sigterm);
      try {
        await process.exitCode.timeout(stopTimeout);
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode.timeout(killTimeout);
      }
    } on TimeoutException {
      throw const LegionControlUnavailableException(
        'Portable helper shutdown could not be confirmed. Restart the app before retrying.',
      );
    } finally {
      await Future.wait([
        process.stdin.close(),
        if (_stdoutSubscription case final output?) output.cancel(),
        if (_stderrSubscription case final errors?) errors.cancel(),
      ]);
    }
  }
}
