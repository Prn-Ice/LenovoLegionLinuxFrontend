import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/control_endpoint.dart';
import 'host_command_environment.dart';
import 'legion_control_client.dart';

typedef HelperProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  required Map<String, String> environment,
  required String workingDirectory,
  required bool includeParentEnvironment,
});

enum HelperSession {
  hardwareControl('--control'),
  packagePower('--package-power');

  const HelperSession(this.argument);
  final String argument;
}

/// Owns the ordinary-user launcher and its bounded readiness exchange.
/// The native launcher obtains host approval and supervises the root helper.
class ControlLauncher {
  ControlLauncher({
    String? executable,
    this.session = HelperSession.hardwareControl,
    HelperProcessStarter? startProcess,
    Map<String, String>? environment,
    this.startupTimeout = const Duration(seconds: 70),
    this.stopTimeout = const Duration(seconds: 3),
    this.killTimeout = const Duration(seconds: 2),
  }) : executable =
           executable ??
           '${File(Platform.resolvedExecutable).parent.path}/libexec/legion-control-helper',
       _startProcess = startProcess ?? Process.start,
       _environment = hostCommandEnvironment(
         environment ?? Platform.environment,
       );

  final String executable;
  final HelperSession session;
  final Duration startupTimeout;
  final Duration stopTimeout;
  final Duration killTimeout;
  final HelperProcessStarter _startProcess;
  final Map<String, String> _environment;
  final _ready = Completer<ControlEndpoint>();
  final _ended = Completer<LegionControlException>();
  final _stdoutDone = Completer<void>();
  final _stderrDone = Completer<void>();
  final _line = <int>[];
  final _stderr = <int>[];
  StreamSubscription<List<int>>? _stdoutSubscription;
  StreamSubscription<List<int>>? _stderrSubscription;
  Future<ControlEndpoint>? _starting;
  Future<void>? _stopping;
  Process? _process;
  ControlEndpoint? _endpoint;
  String? _unit;
  int? _exitCode;
  int _stdoutBytes = 0;
  bool _acknowledged = false;
  bool _closed = false;

  /// Completes with the reason the session ended, including explicit close.
  Future<LegionControlException> get ended => _ended.future;

  LegionControlUnavailableException _closedError() =>
      const LegionControlUnavailableException(
        'Hardware control startup closed. Start a new app session to retry.',
      );

  Future<ControlEndpoint> start() {
    if (_closed) return Future.error(_closedError());
    return _starting ??= _start();
  }

  Future<ControlEndpoint> _start() async {
    try {
      return await Future.any([
        _spawnAndRead(),
        _ended.future.then<ControlEndpoint>((error) => throw error),
      ]).timeout(startupTimeout);
    } on TimeoutException {
      await close();
      throw const LegionControlTimeoutException(
        'Hardware control startup timed out. Check the authentication prompt and start a new app session to retry.',
      );
    } catch (_) {
      await close();
      rethrow;
    }
  }

  Future<ControlEndpoint> _spawnAndRead() async {
    if (!executable.startsWith('/')) {
      throw const LegionControlSetupException(
        'The app helper must have an absolute path inside the app bundle.',
      );
    }
    Process process;
    try {
      process = await _startProcess(
        executable,
        [session.argument],
        environment: _environment,
        workingDirectory: '/',
        includeParentEnvironment: false,
      );
    } on ProcessException catch (error) {
      throw LegionControlSetupException(
        'Could not start the privileged control helper. Reinstall a complete app build and check its host libraries. Hardware readings remain available. $error',
      );
    }
    _process = process;
    _stdoutSubscription = process.stdout.listen(
      _consumeStdout,
      onError: (Object error) => _fail(
        LegionControlSetupException(
          'Could not read app helper readiness: $error',
        ),
      ),
      onDone: () {
        _stdoutDone.complete();
        if (!_closed && _line.isNotEmpty) {
          _fail(
            const LegionControlSetupException(
              'The app helper ended with an incomplete readiness message.',
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
              'App helper diagnostics exceeded 8 KiB.',
            ),
          );
        } else {
          _stderr.addAll(bytes);
        }
      },
      onError: (Object error) {
        _fail(
          LegionControlSetupException(
            'Could not read app helper diagnostics: $error',
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
      r'legion-(?:control-helper|bootstrap-probe)-[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\.service';
  static final _snapshot = RegExp(
    '^SNAPSHOT_READY launcher=([1-9][0-9]*) unit=($_unitPattern)\$',
  );
  static final _control = RegExp(
    '^CONTROL_READY helper=([1-9][0-9]*) unit=($_unitPattern) address=(\\S+) bus=(:[0-9]+\\.[0-9]+)(?: cli=(\\S+))?\$',
  );

  void _consumeStdout(List<int> bytes) {
    if (_closed) return;
    _stdoutBytes += bytes.length;
    if (_stdoutBytes > 64 * 1024) {
      _fail(
        const LegionControlSetupException(
          'App helper readiness exceeded 64 KiB.',
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
              'The app helper returned invalid readiness text.',
            ),
          );
        }
      } else if (_line.length >= 4096) {
        _fail(
          const LegionControlSetupException(
            'A app helper readiness line exceeded 4 KiB.',
          ),
        );
        return;
      } else {
        _line.add(byte);
      }
    }
  }

  void _readLine(String line) {
    const setupPrefix = 'CONTROL_SETUP_ERROR ';
    if (_endpoint == null && line.startsWith(setupPrefix)) {
      _fail(LegionControlSetupException(line.substring(setupPrefix.length)));
      return;
    }
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
      final cliPath = control[5] == null
          ? null
          : Uri.decodeComponent(control[5]!);
      if ((session == HelperSession.packagePower && cliPath != null) ||
          (session == HelperSession.hardwareControl &&
              control[2]!.startsWith('legion-control-helper-') &&
              cliPath == null) ||
          (cliPath != null &&
              (!cliPath.startsWith('/') || cliPath.contains('\u0000')))) {
        _fail(
          const LegionControlSetupException(
            'The helper did not report a valid installed CLI. Update the app files and retry.',
          ),
        );
        return;
      }
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
            'App helper identity does not match its launch.',
          ),
        );
        return;
      }
      _endpoint = ControlEndpoint(
        address: control[3]!,
        unit: control[2]!,
        helperPid: pid,
        busName: control[4]!,
        cliPath: cliPath,
      );
    } else {
      _fail(
        const LegionControlSetupException(
          'Unexpected app helper readiness message.',
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
    var outputComplete = false;
    if (!_ready.isCompleted) {
      try {
        await Future.wait([_stdoutDone.future, _stderrDone.future])
            .timeout(const Duration(seconds: 1));
        outputComplete = true;
      } on TimeoutException {
        /* Report exit with diagnostics received so far. */
      }
    }
    if (_closed) return;
    final startupFailed = !_ready.isCompleted;
    final details = utf8.decode(_stderr, allowMalformed: true).trim();
    final message = 'App helper exited with status $_exitCode. $details'.trim();
    final LegionControlException error;
    if (details.contains('org.freedesktop.DBus.Error.AccessDenied')) {
      // A rejected start cannot have created a helper or accepted any writes.
      error =
          startupFailed &&
              outputComplete &&
              _unit != null &&
              !_acknowledged &&
              _endpoint == null
          ? LegionControlStartupDeniedException(message)
          : LegionControlPermissionDeniedException(message);
    } else {
      error = startupFailed
          ? LegionControlSetupException(message)
          : LegionControlUnavailableException(message);
    }
    _fail(error);
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
    // Dart cannot cancel Process.start; _spawnAndRead stops a late child.
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
        'Could not confirm app helper shutdown. Restart the app before retrying.',
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
